"use strict";

const LANGUAGES = { en: "English", fr: "Français", it: "Italiano", de: "Deutsch", es: "Español" };
const $ = (id) => document.getElementById(id);

let messages = {};
let user = null;

function t(key, vars = {}) {
  let text = messages[key] || key;
  for (const [name, value] of Object.entries(vars)) {
    text = text.replace(`{${name}}`, value);
  }
  return text;
}

function storedLanguage() {
  try { return localStorage.getItem("privatebin-auth-lang"); } catch (e) { return null; }
}

function pickLanguage() {
  const stored = storedLanguage();
  if (stored && LANGUAGES[stored]) return stored;
  for (const tag of navigator.languages || [navigator.language || "en"]) {
    const code = tag.slice(0, 2).toLowerCase();
    if (LANGUAGES[code]) return code;
  }
  return "en";
}

async function loadLanguage(code) {
  const response = await fetch(`/_auth/i18n/${code}.json`);
  messages = await response.json();
  document.documentElement.lang = code;
  for (const node of document.querySelectorAll("[data-i18n]")) {
    node.textContent = t(node.dataset.i18n);
  }
  updatePasswordToggle();
  render();
}

function updatePasswordToggle() {
  const shown = $("password").type === "text";
  const button = $("toggle-password");
  button.setAttribute("aria-pressed", String(shown));
  button.setAttribute("aria-label", t(shown ? "hide_password" : "show_password"));
  button.title = button.getAttribute("aria-label");
}

function togglePassword() {
  const input = $("password");
  input.type = input.type === "password" ? "text" : "password";
  updatePasswordToggle();
  input.focus();
}

async function api(path, options = {}) {
  const response = await fetch(path, { credentials: "same-origin", ...options });
  let body = null;
  if (response.status !== 204) {
    try { body = await response.json(); } catch (e) { body = null; }
  }
  return { status: response.status, body };
}

function render() {
  $("login-view").hidden = Boolean(user);
  $("user-view").hidden = !user;
  if (user) $("user").textContent = t("logged_in", { name: user.display_name || user.name });
}

async function login(event) {
  event.preventDefault();
  const button = event.submitter || $("login-form").querySelector("button[type=submit]");
  const error = $("login-error");
  error.hidden = true;
  button.disabled = true;
  const result = await api("/_auth/api/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      username: $("username").value,
      password: $("password").value,
      remember: $("remember").checked,
    }),
  });
  button.disabled = false;
  $("password").value = "";
  // Never leave a revealed password field behind after a login attempt
  $("password").type = "password";
  updatePasswordToggle();
  if (result.status === 200) {
    location.assign("/");
    return;
  }
  error.textContent = t({ 401: "login_invalid", 429: "login_blocked" }[result.status] || "login_error");
  error.hidden = false;
}

async function logout() {
  await api("/_auth/api/logout", { method: "POST" });
  user = null;
  render();
  $("username").focus();
}

async function main() {
  const lang = pickLanguage();
  const select = $("lang");
  for (const [code, label] of Object.entries(LANGUAGES)) {
    const option = document.createElement("option");
    option.value = code;
    option.textContent = label;
    select.append(option);
  }
  select.value = lang;
  select.addEventListener("change", () => {
    try { localStorage.setItem("privatebin-auth-lang", select.value); } catch (e) { /* private mode */ }
    loadLanguage(select.value);
  });
  $("hostname").textContent = location.hostname;
  $("login-form").addEventListener("submit", login);
  $("logout").addEventListener("click", logout);
  $("toggle-password").addEventListener("click", togglePassword);

  user = ((await api("/_auth/api/session")).body || {}).user || null;
  await loadLanguage(lang);
  if (!user) $("username").focus();
}

main();
