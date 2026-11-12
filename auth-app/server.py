#!/usr/bin/env python3

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#

# LDAP login in front of PrivateBin. nginx asks /_auth/check before each
# request (auth_request) and proxies the login page under /_auth/.

import base64
import hashlib
import hmac
import json
import os
import re
import signal
import sys
import threading
import time
from http import HTTPStatus
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import ldap3
from ldap3.utils.conv import escape_filter_chars

STATIC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")
LISTEN_ADDRESS = os.environ.get("AUTH_LISTEN", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("AUTH_PORT", "9080"))

SESSION_SECRET = os.environ.get("SESSION_SECRET", "").encode()
SESSION_COOKIE = "privatebin_session"
SESSION_TTL = 8 * 3600
REMEMBER_TTL = 7 * 24 * 3600
# A session reads the account again from LDAP at most this often, so a locked
# or removed account loses access soon. nginx drops the Set-Cookie of an
# auth_request answer, so the result is cached here and not in the cookie.
RECHECK_INTERVAL = 3600
# While LDAP is down, wait this long before the next try instead of
# stalling every request on the connect timeout
RETRY_INTERVAL = 60

LDAP_HOST = os.environ.get("LDAP_HOST", "")
LDAP_PORT = int(os.environ.get("LDAP_PORT", "0") or 0)
LDAP_BIND_DN = os.environ.get("LDAP_USER", "")
LDAP_BIND_PASSWORD = os.environ.get("LDAP_PASS", "")
LDAP_BASE = os.environ.get("LDAP_BASE", "")
LDAP_SCHEMA = os.environ.get("LDAP_SCHEMA", "rfc2307")
# Service accounts like ldapservice or Guest, hidden by ldapproxy
LDAP_HIDDEN_USERS = {u.lower() for u in os.environ.get("LDAP_HIDDEN_USERS", "").split(",") if u}

# Brute force guard: after MAX_FAILURES failed logins from one IP inside
# FAILURE_WINDOW seconds, the login answers 429 until the window expires.
# Kept above the 5 POST 401 that CrowdSec http-generic-401-bf needs to ban,
# so a fast attack still reaches CrowdSec as 401 before it turns into 429.
MAX_FAILURES = 10
FAILURE_WINDOW = 900

STATIC_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".json": "application/json; charset=utf-8",
}

SAFE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,120}$")
CLEAR_COOKIE = f"{SESSION_COOKIE}=; Path=/; Max-Age=0; HttpOnly; Secure; SameSite=Lax"

failures = {}
failures_lock = threading.Lock()
# uid -> (time of the last LDAP check, account still valid)
checks = {}
checks_lock = threading.Lock()


def log(message):
    print(message, file=sys.stderr, flush=True)


def needs_login(method, uri):
    """Creating a document or a comment needs a login, reading a link does not."""
    if method not in ("GET", "HEAD"):
        return True
    path, _, query = uri.partition("?")
    # The editor page: a document link always carries its id in the query
    return path in ("/", "/index.php") and not query


def sign(payload):
    return hmac.new(SESSION_SECRET, payload, hashlib.sha256).hexdigest()


def session_cookie(user, display_name, remember):
    now = int(time.time())
    payload = json.dumps({
        "u": user, "n": display_name, "c": now,
        "e": now + (REMEMBER_TTL if remember else SESSION_TTL),
    }).encode()
    data = base64.urlsafe_b64encode(payload).decode().rstrip("=")
    value = data + "." + sign(data.encode())
    # Without "keep me logged in" the cookie dies with the browser, and the
    # server still refuses it after SESSION_TTL
    max_age = f"Max-Age={REMEMBER_TTL}; " if remember else ""
    return f"{SESSION_COOKIE}={value}; Path=/; {max_age}HttpOnly; Secure; SameSite=Lax"


def read_session(value):
    if not value or "." not in value or not SESSION_SECRET:
        return None
    data, signature = value.rsplit(".", 1)
    if not hmac.compare_digest(sign(data.encode()), signature):
        return None
    try:
        session = json.loads(base64.urlsafe_b64decode(data + "=" * (-len(data) % 4)))
    except ValueError:
        return None
    if session.get("e", 0) < time.time():
        return None
    return session


def too_many_failures(ip):
    now = time.time()
    with failures_lock:
        # Prune every address, or a spread out attack would grow the dict forever
        for key in list(failures):
            failures[key] = [t for t in failures[key] if now - t < FAILURE_WINDOW]
            if not failures[key]:
                del failures[key]
        return len(failures.get(ip, [])) >= MAX_FAILURES


def record_failure(ip):
    with failures_lock:
        failures.setdefault(ip, []).append(time.time())


def clear_failures(ip):
    with failures_lock:
        failures.pop(ip, None)


def ldap_connection(user=None, password=None):
    server = ldap3.Server(LDAP_HOST, port=LDAP_PORT, connect_timeout=5)
    return ldap3.Connection(server, user=user, password=password, auto_bind=True,
                            raise_exceptions=True, receive_timeout=10, read_only=True)


def ldap_find_user(conn, username):
    """Return (dn, uid, display_name), or None when the user does not exist or is locked."""
    if LDAP_SCHEMA == "ad":
        user_filter = f"(&(objectClass=user)(objectCategory=person)(sAMAccountName={escape_filter_chars(username)}))"
        attributes = ["sAMAccountName", "displayName", "userAccountControl"]
    else:
        user_filter = f"(&(objectClass=posixAccount)(objectClass=inetOrgPerson)(uid={escape_filter_chars(username)}))"
        attributes = ["uid", "displayName", "cn", "pwdAccountLockedTime"]
    conn.search(LDAP_BASE, user_filter, attributes=attributes)
    if len(conn.entries) != 1:
        return None
    entry = conn.entries[0]
    if username.lower() in LDAP_HIDDEN_USERS:
        return None
    if LDAP_SCHEMA == "ad":
        if int(entry.userAccountControl.value or 0) & 0x2:
            return None
        uid = str(entry.sAMAccountName.value)
        return entry.entry_dn, uid, str(entry.displayName.value or uid)
    if entry.pwdAccountLockedTime.value:
        return None
    uid = str(entry.uid.value)
    return entry.entry_dn, uid, str(entry.displayName.value or entry.cn.value or uid)


def ldap_authenticate(username, password):
    """Return (uid, display_name) or None when the credentials are wrong."""
    username = username.strip()
    # An empty password would turn the user bind into an anonymous bind that succeeds
    if not username or not password or not LDAP_HOST:
        return None
    with ldap_connection(LDAP_BIND_DN, LDAP_BIND_PASSWORD) as conn:
        found = ldap_find_user(conn, username)
    if not found:
        return None
    user_dn, uid, display_name = found
    try:
        ldap_connection(user_dn, password).unbind()
    except (ldap3.core.exceptions.LDAPBindError, ldap3.core.exceptions.LDAPInvalidCredentialsResult):
        return None
    return uid, display_name


def account_valid(uid):
    """Read the account again from LDAP when the cached answer is too old."""
    now = time.time()
    with checks_lock:
        checked, valid = checks.get(uid, (0, True))
    if now - checked < RECHECK_INTERVAL:
        return valid
    # Other requests of this user keep the cached answer during the check
    with checks_lock:
        checks[uid] = (now, valid)
    try:
        with ldap_connection(LDAP_BIND_DN, LDAP_BIND_PASSWORD) as conn:
            valid = ldap_find_user(conn, uid) is not None
    except ldap3.core.exceptions.LDAPException as ex:
        # LDAP is down: keep the last answer, try again after RETRY_INTERVAL
        log(f"LDAP error: {ex}")
        with checks_lock:
            checks[uid] = (now - RECHECK_INTERVAL + RETRY_INTERVAL, valid)
        return valid
    with checks_lock:
        checks[uid] = (now, valid)
    if not valid:
        log(f"session revoked user={uid!r}")
    return valid


def mark_checked(uid):
    with checks_lock:
        checks[uid] = (time.time(), True)


class Handler(BaseHTTPRequestHandler):
    server_version = "privatebin-auth"
    sys_version = ""
    protocol_version = "HTTP/1.1"

    def client_ip(self):
        # Only nginx in the same pod reaches us, it sets the visitor address
        return self.headers.get("X-Real-IP", "").strip() or self.client_address[0]

    def log_message(self, format, *args):
        pass

    def log_request(self, code="-", size="-"):
        # The check runs before every request: logging it would flood the journal
        if self.path.startswith("/_auth/check"):
            return
        duration = int((time.monotonic() - getattr(self, "started", time.monotonic())) * 1000)
        path = self.path.split("?", 1)[0]
        log(f'{self.client_ip()} "{self.command} {path}" {int(code)} {duration}ms')

    def send(self, status, body=b"", content_type="application/json; charset=utf-8", headers=None):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "same-origin")
        self.send_header("Content-Security-Policy",
                         "default-src 'self'; style-src 'self'; script-src 'self'; frame-ancestors 'none'")
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def send_json(self, status, payload, headers=None):
        self.send(status, json.dumps(payload).encode(), headers=headers)

    def send_file(self, path):
        content_type = STATIC_TYPES.get(os.path.splitext(path)[1])
        if not content_type or not os.path.isfile(path):
            return self.send_json(HTTPStatus.NOT_FOUND, {"error": "not_found"})
        with open(path, "rb") as fp:
            self.send(HTTPStatus.OK, fp.read(), content_type)

    def session(self):
        cookie = SimpleCookie(self.headers.get("Cookie", ""))
        morsel = cookie.get(SESSION_COOKIE)
        session = read_session(morsel.value if morsel else "")
        if session and not account_valid(session["u"]):
            return None
        return session

    def read_body(self):
        """Read the request body, or close the connection when it cannot be
        read whole: unread bytes would be parsed as the next request."""
        try:
            length = int(self.headers.get("Content-Length", "0") or 0)
        except ValueError:
            length = -1
        if self.headers.get("Transfer-Encoding") or length < 0 or length > 4096:
            self.close_connection = True
            return None
        raw = self.rfile.read(length) if length else b""
        try:
            return json.loads(raw)
        except ValueError:
            return None

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        self.started = time.monotonic()
        self.read_body()
        path = self.path.split("?", 1)[0]
        if path == "/_auth/check":
            return self.check()
        if path == "/_auth/login":
            return self.send_file(os.path.join(STATIC_DIR, "index.html"))
        if path == "/_auth/api/session":
            session = self.session()
            return self.send_json(HTTPStatus.OK, {
                "user": {"name": session["u"], "display_name": session["n"]} if session else None,
            })
        match = re.match(r"^/_auth/(static|i18n)/([^/]+)$", path)
        if match and SAFE_NAME.match(match.group(2)):
            folder = STATIC_DIR if match.group(1) == "static" else os.path.join(STATIC_DIR, "i18n")
            return self.send_file(os.path.join(folder, match.group(2)))
        return self.send_json(HTTPStatus.NOT_FOUND, {"error": "not_found"})

    def do_POST(self):
        self.started = time.monotonic()
        # Read it before any early answer, so the connection stays in sync
        body = self.read_body()
        path = self.path.split("?", 1)[0]
        if path == "/_auth/api/login":
            return self.api_login(body)
        if path == "/_auth/api/logout":
            return self.send(HTTPStatus.NO_CONTENT, headers={"Set-Cookie": CLEAR_COOKIE})
        return self.send_json(HTTPStatus.NOT_FOUND, {"error": "not_found"})

    def check(self):
        method = self.headers.get("X-Original-Method", "")
        uri = self.headers.get("X-Original-URI", "")
        if not needs_login(method, uri) or self.session():
            return self.send(HTTPStatus.NO_CONTENT)
        return self.send(HTTPStatus.UNAUTHORIZED)

    def api_login(self, body):
        # A cross-site form cannot send JSON without a CORS preflight, which
        # we never allow: this blocks logging a victim into another account
        if self.headers.get("Content-Type", "").split(";")[0].strip().lower() != "application/json":
            return self.send_json(HTTPStatus.UNSUPPORTED_MEDIA_TYPE, {"error": "json_required"})
        ip = self.client_ip()
        if too_many_failures(ip):
            log(f"login blocked ip={ip}")
            return self.send_json(HTTPStatus.TOO_MANY_REQUESTS, {"error": "too_many_attempts"},
                                  headers={"Retry-After": str(FAILURE_WINDOW)})
        if not isinstance(body, dict) or not isinstance(body.get("username"), str) \
                or not isinstance(body.get("password"), str):
            return self.send_json(HTTPStatus.BAD_REQUEST, {"error": "bad_request"})
        username = body["username"][:256]
        remember = body.get("remember") is True
        if not LDAP_HOST:
            log(f"login refused user={username!r} ip={ip}: user domain not available")
            return self.send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": "ldap_unavailable"})
        try:
            result = ldap_authenticate(username, body["password"])
        except ldap3.core.exceptions.LDAPException as ex:
            log(f"LDAP error: {ex}")
            return self.send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"error": "ldap_unavailable"})
        if not result:
            record_failure(ip)
            log(f"login failed user={username!r} ip={ip}")
            return self.send_json(HTTPStatus.UNAUTHORIZED, {"error": "invalid_credentials"})
        clear_failures(ip)
        uid, display_name = result
        mark_checked(uid)
        log(f"login ok user={uid!r} ip={ip} remember={remember}")
        self.send_json(HTTPStatus.OK, {"name": uid, "display_name": display_name},
                       headers={"Set-Cookie": session_cookie(uid, display_name, remember)})


if __name__ == "__main__":
    if not SESSION_SECRET:
        log("SESSION_SECRET is missing: cannot sign sessions")
        sys.exit(1)
    # As PID 1 in the container, Python would otherwise ignore the SIGTERM of podman stop
    signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))
    log(f"privatebin-auth listening on {LISTEN_ADDRESS}:{LISTEN_PORT}")
    ThreadingHTTPServer((LISTEN_ADDRESS, LISTEN_PORT), Handler).serve_forever()
