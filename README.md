# ns8-privatebin

[PrivateBin](https://privatebin.info/) for [NethServer 8](https://github.com/NethServer/ns8-core).
PrivateBin shares text and files with end-to-end encryption: documents are
encrypted in the browser and the server never sees their content.

The module runs the official `privatebin/nginx-fpm-alpine` image in one
rootless container with a read-only root filesystem. It needs no database and
no user domain. Documents are stored as files in the `privatebin-data` volume.

## Install

    add-module ghcr.io/stephdl/privatebin:latest 1

The output returns the instance name:

    {"module_id": "privatebin1", "image_name": "privatebin", "image_url": "ghcr.io/stephdl/privatebin:latest"}

## Configure

Open the instance Settings page in cluster-admin, or call `configure-module`.
Every field is required except `logo`:

```
api-cli run module/privatebin1/configure-module --data - <<'EOF'
{
  "host": "privatebin.example.org",
  "lets_encrypt": true,
  "private_creators": true,
  "rate_limit": 30,
  "name": "PrivateBin",
  "notice": "",
  "info": "",
  "expire_default": "1week",
  "expire_max": "1year",
  "discussion": false,
  "open_discussion": false,
  "burn_after_reading_selected": false,
  "qrcode": true,
  "file_upload": false,
  "size_limit": 10,
  "language_selection": true,
  "language_default": "auto"
}
EOF
```

| Field | Default | Meaning |
|---|---|---|
| `host` | | Host name of the Traefik route. HTTPS is always forced. |
| `lets_encrypt` | `false` | Request a Let's Encrypt certificate. |
| `private_creators` | `true` | Only private networks can create documents, see below. |
| `rate_limit` | `30` | Seconds between two documents from the same address, 10 to 300, `0` for no delay. Ignored when `private_creators` is on. |
| `name` | `PrivateBin` | Service name in the browser title and the navigation bar. |
| `notice` | empty | Plain text banner above the editor. |
| `info` | empty | Footer text, HTML allowed. |
| `expire_default` | `1week` | Expiration selected by default. |
| `expire_max` | `1year` | Longest expiration offered. Longer ones, `never` included, are removed from the list. |
| `discussion` | `false` | Allow comments under documents. |
| `open_discussion` | `false` | Preselect the discussion option. |
| `burn_after_reading_selected` | `false` | Preselect burn after reading. |
| `qrcode` | `true` | Offer a QR code of the document link. |
| `file_upload` | `false` | Allow attachments. Several files per document are accepted. |
| `size_limit` | `10` | Maximum encrypted document size in MiB, 1 to 50. |
| `language_selection` | `true` | Show the language menu. |
| `language_default` | `auto` | Language code like `fr`, or `auto` for the browser language. |
| `logo` | | Base64 PNG or JPEG of at most 512 KB for the navigation bar. `""` restores the original logo, a missing key keeps the current one. |

The module writes `conf.php`, the PHP and nginx limits and the logo from these
settings, then restarts PrivateBin. No upstream file is changed, so image
updates stay safe. The settings are kept in `state/privatebin/settings.json`
because free HTML in the footer would break the systemd environment file.

## Abuse protection

PrivateBin has no login, no captcha and no content filter: the server cannot
read the documents. The module protects the disk in these ways.

**Private creation**, on by default. Only clients from `10.0.0.0/8`,
`172.16.0.0/12`, `192.168.0.0/16`, `fc00::/7` and the loopback can create
documents and comments. They have no delay. Other addresses get "Your IP is not
authorized to create documents". Anyone can still open a link, so a document
can be shared with someone outside. This is PrivateBin's `[traffic] creators`
option.

**Delay between documents**, only when private creation is off. After a
document or a comment, the same address must wait `rate_limit` seconds,
otherwise PrivateBin answers "Please wait N seconds between each post". This
slows down a bot that posts in a loop. It does not stop a bot with many
addresses. This is PrivateBin's `[traffic] limit` option. PrivateBin skips it
for the `creators` networks, which is why the UI hides it in private mode.

**Visitor address.** Traefik replaces any `X-Forwarded-For` sent by the client.
nginx reads that header from the right and skips the private hops, so the
first public address is the visitor, also behind Traefik trusted proxies. A
front proxy with a public address, like a cloud load balancer, is seen as the
visitor itself.

**Size and lifetime.** The size limit, the longest expiration and a daily
`privatebin-purge.timer` keep the storage bounded. PrivateBin itself purges
expired documents only when someone creates one.

**Discussions** are off by default, comments are another way to post content.

**CrowdSec**, when installed on the node, reads the Traefik logs. Tests on a
node showed that it bans path scans and exploit probes in seconds, but a flood
of valid document creations triggers no scenario. Do not rely on it against
spam.

To remove an abusive document, take its ID from the URL, the part between `?`
and `#`:

    runagent -m privatebin1 podman exec privatebin-app administration --delete <id>

`administration --statistics` and `administration --purge` also work.

## Upload size and Traefik

The PHP and nginx limits follow `size_limit`. Traefik cuts any request that
takes more than 60 seconds, its default read timeout, and a module cannot
change it. A 50 MiB document needs about 9 Mbit/s of upload speed.

## Backup, restore and clone

The backup holds `settings.json`, the custom logo and the `privatebin-data`
volume, which contains the documents, the comments and the server salt. The
other files are generated again on restore.

A restore or a plain clone keeps the source host. When that host is already
used on the cluster, the instance gets no route: Settings shows a warning, and
saving a new host name publishes it.

## Uninstall

    remove-module --no-preserve privatebin1

## Debug

    runagent -m privatebin1 systemctl --user status privatebin.service privatebin-app.service privatebin-purge.timer
    runagent -m privatebin1 cat privatebin/conf.php
    journalctl _UID=$(id -u privatebin1)

## Testing

Test the module using the `test-module.sh` script:

    ./test-module.sh <NODE_ADDR> ghcr.io/stephdl/privatebin:latest

The tests are made using [Robot Framework](https://robotframework.org/).

## UI translation

Translated with [Weblate](https://hosted.weblate.org/projects/ns8/).
