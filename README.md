# Postiz for Home Assistant OS

A Home Assistant **app** repository ("add-ons" in older wording) that runs
self-hosted [Postiz](https://github.com/gitroomhq/postiz-app) and everything it
needs as ordinary **Supervisor-managed** containers. No Docker-in-Docker, no
Docker socket, no Portainer, no privileged mode, no host networking, no changes
to your Home Assistant configuration.

```
Home Assistant Supervisor  (internal "hassio" network, not reachable from the LAN)
│
├── Postiz PostgreSQL 16 ─ databases: postiz | temporal | temporal_visibility
│        ▲      ▲
│        │      └──────────── Postiz Temporal 1.28.4 (workflows, SQL visibility)
│        │                         ▲
├── Postiz Redis 7.2               │ gRPC :7233
│        ▲                         │
│        └──── Postiz v2.25.0 ─────┘
│                 │
│                 └── LAN port 4007 ──► your browser / later your HTTPS proxy
│
└── Temporal UI (optional, manual start, LAN port 8233)
```

| App | Upstream image | LAN port | Data it keeps |
|---|---|---|---|
| Postiz PostgreSQL | `postgres:16.15-trixie` | none | all Postiz + Temporal data |
| Postiz Redis | `redis:7.2.16-bookworm` | none | nothing important (cache) |
| Postiz Temporal | `temporalio/auto-setup:1.28.4` | none | none (state is in PostgreSQL) |
| Postiz | `ghcr.io/gitroomhq/postiz-app:v2.25.0` | **4007** | uploaded media, JWT secret |
| Temporal UI for Postiz *(optional)* | `temporalio/ui:2.34.0` | 8233 | none |

Every wrapper is thin: it reads the app options, waits for its dependencies
and then runs the **unmodified upstream entrypoint**. How and why the design
was chosen (including what was tested) is in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). The full test checklist is in
[docs/TEST-PLAN.md](docs/TEST-PLAN.md).

Contents:
[Requirements](#requirements) ·
[5 Install](#part-5---installation) ·
[6 Configure](#part-6---initial-configuration) ·
[7 Start](#part-7---starting-the-stack) ·
[8 Verify](#part-8---verifying-everything-works) ·
[9 HTTPS](#part-9---setting-up-external-https-later) ·
[10 Providers](#part-10---social-provider-configuration) ·
[11 Backup](#part-11---backup-and-restore) ·
[12 Update](#part-12---updating) ·
[13 Troubleshooting](#part-13---troubleshooting) ·
[14 Removal](#part-14---rollback--complete-removal) ·
[15 Limitations](#part-15---known-limitations)

---

## Requirements

- Home Assistant OS on **amd64** with Supervisor **2026.07 or newer** (the
  Postiz app uses the `app_config` folder mapping introduced then). Tested
  configuration target: HAOS 18.3 / Supervisor 2026.09.3.
- **RAM:** expect about **1.2-2 GB** for the whole suite (Postiz alone is
  0.9-1.5 GB; it runs three Node.js processes and ~30 Temporal workers).
  A 16 GB machine is fine; this is not a tiny app.
- **Disk:** about **6.5 GB** of images (Postiz alone is ~5 GB) plus your
  media. Database growth for one user is small (well under 1 GB/year).
- Internet access for the Postiz app at start-up (Postiz downloads the Prisma
  CLI from npm when it is not cached).

None of the apps needs `hassio_api`, `homeassistant_api`, `docker_api`,
`privileged`, `host_network`, `full_access`, extra AppArmor rules or access to
`/config`, `/share`, `/media`, USB or GPIO. Each one sees only its own data
folder (and Postiz its own app-config folder).

---

## Part 5 - Installation

Nothing in this part changes Home Assistant itself.

### 5.1 Put the repository on GitHub

1. Create a GitHub repository, e.g. `postiz-ha-addon` (public is simplest;
   Supervisor can also use a private repo with a token in the URL, but
   public avoids that).
2. Copy all files from this folder into it.
3. Edit `repository.yaml` and replace `YOUR_GITHUB_USERNAME`.
4. Commit and push.

> Alternative for a quick local test without GitHub: copy the five app
> folders into the `addons` share (Samba; newer Samba versions may call it
> `local_apps`) and use **Check for updates** in the
> app store - they appear under **Local apps**. Discovery works the same way
> (the prefix is then `local`). Use only one of the two methods.

### 5.2 Add the repository to Home Assistant

**Settings > Apps > App store > ⋮ (top right) > Repositories**, paste
`https://github.com/jmocs94/postiz-ha-addon`, **Add**, close,
then **⋮ > Check for updates**. A section **Postiz for Home Assistant**
appears.

### 5.3 Install the apps (in this order)

1. **Postiz PostgreSQL**
2. **Postiz Redis**
3. **Postiz Temporal**
4. **Postiz** - this one is slow: Supervisor builds it locally, which first
   downloads the ~5 GB official Postiz image. Ten minutes or more is normal.
5. *(optional, only if you want it)* **Temporal UI for Postiz**

Installing only builds the images; nothing runs yet.

---

## Part 6 - Initial configuration

### 6.1 Make three passwords

Open the **Advanced SSH & Web Terminal** app (or any computer) and run:

```sh
for name in postiz-db temporal-db redis; do printf '%-12s %s\n' "$name" "$(openssl rand -hex 24)"; done
```

Passwords must be 16-128 characters from `A-Z a-z 0-9 . _ ~ -` (hex output
always qualifies). Keep them in your password manager. Never paste them into
a GitHub issue or this repository.

### 6.2 Enter them - each one in two places

Supervisor deliberately does not let one app read another app's settings
(that would need the powerful `manager` role), so the same password is typed
into the server app and the client app:

| Password | Server app → option | Client app → option |
|---|---|---|
| postiz-db | Postiz PostgreSQL → `postiz_password` | Postiz → `database_password` |
| temporal-db | Postiz PostgreSQL → `temporal_password` | Postiz Temporal → `database_password` |
| redis | Postiz Redis → `password` | Postiz → `redis_password` |

### 6.3 Postiz options

On **Postiz > Configuration**:

| Option | Value for the first test |
|---|---|
| External URL | `http://<HA-IP>:4007` - exactly what you will type in the browser, e.g. `http://192.168.55.65:4007` |
| Database password | postiz-db |
| Redis password | redis |
| Disable registration | on (the first account can still be created - see below) |
| Media storage | local |
| E-mail provider | none |

Leave **JWT secret** empty: a long random secret is generated on first start
and stored in the app's data folder; it never changes unless you set one
yourself. Social-provider fields stay empty for now (they are under
"Show unused optional configuration options").

Database host names are discovered automatically - there are no connection
strings to write.

---

## Part 7 - Starting the stack

Start the apps **in this order** and watch each **Log** tab until it reports
ready:

| # | App | Ready when the log shows |
|---|---|---|
| 1 | Postiz PostgreSQL | `database system is ready to accept connections` |
| 2 | Postiz Redis | `Ready to accept connections` |
| 3 | Postiz Temporal | `[postiz-temporal] Temporal is ready: frontend on port 7233, namespace 'default' available.` |
| 4 | Postiz | `[postiz] Postiz is ready: backend and frontend answer on port 5000. Open http://...` |

The order only matters for the very first start; afterwards each app simply
waits (with a time limit) for the ones it depends on.

### Start on boot and Watchdog

- **Start on boot**: on (the default) for PostgreSQL, Redis, Temporal and
  Postiz. Supervisor starts PostgreSQL and Redis before Home Assistant Core
  (`startup: system`) and Temporal and Postiz after it (`startup:
  application`), so Postiz never slows down Home Assistant's own start.
  Temporal UI is `manual` and never starts on boot.
- **Watchdog**: turn it on for the four main apps **after** the first
  successful start. It restarts an app that crashes, at most 5 times with
  increasing delays, then gives up (no endless restart loops). Leave it off
  for Temporal UI.

---

## Part 8 - Verifying everything works

1. From another computer on your LAN open `http://<HA-IP>:4007`. You are sent
   to `/auth`.
2. Create your account (name, e-mail, password). With e-mail set to `none`
   the account is active immediately.
3. Log out and open `http://<HA-IP>:4007/auth` again: it must now say
   **Registration is disabled**. Your instance is not a public sign-up page.
4. Restart the **Postiz** app; log in again - the account is still there
   (it lives in PostgreSQL).
5. Upload an image in the media library, restart Postiz, check the image still
   displays.
6. Temporal check without any social account: start **Temporal UI for
   Postiz**, open `http://<HA-IP>:8233` > namespace `default` > Workflows. A
   **Running** workflow `missing-post-workflow` proves Postiz is connected to
   Temporal and its workers are polling. Stop Temporal UI again.
7. Scheduling end-to-end: connect one channel that needs no OAuth app (e.g. a
   test **Bluesky** account with an app password, or a Telegram bot via
   `postiz.env`), schedule a post 10 minutes ahead, and watch it publish. In
   Temporal UI it shows up as a workflow `post_<id>`.

The complete checklist (reboot, restart, backup, update and removal tests) is
in [docs/TEST-PLAN.md](docs/TEST-PLAN.md).

---

## Part 9 - Setting up external HTTPS later

The suite does not include a reverse proxy; Postiz only needs to know its
canonical URL. Choose one way to get `https://postiz.example.com` (example) in
front of `http://<HA-IP>:4007`:

**A. Nginx Proxy Manager app (already on your system)**

1. DNS: point `postiz.example.com` at your public IP; forward TCP 80/443 on
   your router to the Home Assistant host (if not already done for NPM).
2. NPM > Hosts > Add Proxy Host: domain `postiz.example.com`, scheme `http`,
   forward host `<HA-IP>`, port `4007`, enable **Websockets Support** and
   **Block Common Exploits**; SSL tab: request a Let's Encrypt certificate,
   **Force SSL**.
3. Advanced tab (for large video uploads): `client_max_body_size 2G;`

**B. Cloudflare Tunnel** (no open ports): point a public hostname at
`http://<HA-IP>:4007`.

**C. Tailscale Funnel** (Tailscale app is already installed): gives a public
`https://<machine>.<tailnet>.ts.net` URL. Fine for OAuth callbacks; note the
hostname is tied to your tailnet.

Then, in all cases:

1. **Postiz > Configuration > External URL** = `https://postiz.example.com`
   (no trailing slash, no path) and restart Postiz. The log should now say
   `HTTPS: secure cookies enabled`.
2. Always open Postiz through that HTTPS URL from now on (cookies are bound
   to it).
3. Register that URL's callback paths with your social providers (Part 10).
4. Optional hardening: once the proxy works you can remove the LAN port
   (Postiz > Network: clear 4007) **only if** your proxy reaches Postiz
   another way. NPM, being an app on the same internal network, can forward to
   `<repo-prefix>-postiz:5000` directly; the exact host name is printed in the
   Postiz log line `This app's hostname: ...`.

Exposing Postiz to the internet makes it a target: keep **Disable
registration** on, use a strong password, and update regularly.

Uploaded media URLs are stored with the URL that was configured at upload
time. Switch to the final HTTPS URL before you build up a media library.

---

## Part 10 - Social provider configuration

- Provider credentials are optional fields on **Postiz > Configuration**
  (X, LinkedIn, Reddit, Facebook/Instagram, Instagram standalone, Threads,
  YouTube, TikTok, Pinterest, Discord, Mastodon). Everything else goes into the
  optional `postiz.env` file. Details, option names and the full list:
  the **Documentation** tab of the Postiz app ([postiz/DOCS.md](postiz/DOCS.md)).
- Redirect / callback URL to register with a provider:
  **`<External URL>/integrations/social/<provider>`**, e.g.
  `https://postiz.example.com/integrations/social/linkedin`,
  `.../linkedin-page`, `.../x`, `.../facebook`, `.../instagram`,
  `.../instagram-standalone`, `.../threads`, `.../youtube`, `.../tiktok`,
  `.../pinterest`, `.../reddit`, `.../discord`, `.../mastodon`.
- Provider walkthroughs (developer-app creation, scopes, review requirements):
  <https://docs.postiz.com/providers/overview>.
- Local `http://IP:4007` is fine for installing and testing, but **most
  providers need a stable HTTPS public hostname** for OAuth, and some (TikTok,
  Instagram) fetch your media from Postiz's public URL.
- After changing provider options, restart the Postiz app.

---

## Part 11 - Backup and restore

### What Home Assistant backs up

| App | Included | Mode | Notes |
|---|---|---|---|
| Postiz PostgreSQL | whole data folder (all databases) | **cold** - stopped during backup | consistent copy; Postiz/Temporal lose the DB for a minute or two and reconnect |
| Postiz | uploads, JWT secret, `postiz.env` | hot | |
| Postiz Redis | (empty unless persistence is on) | hot | nothing important |
| Postiz Temporal | nothing important | hot | Temporal state is in PostgreSQL |
| all apps | the app's options (incl. passwords) | | protect your backup files / use HA backup encryption |

**Backup size warning.** For an app that Supervisor builds locally (the
default in this repository), every backup also contains the app's Docker
image (`image.tar`). The Postiz image is ~5 GB, so each full backup grows by
several GB. Fine for testing; for permanent use switch to prebuilt images
(Part 12) or keep fewer automatic backups.

The apps are backed up one after another, not at the same instant. A post or
upload made during the backup window can end up in one backup and not the
other (for example an uploaded file without its database row). For a
single-user scheduler this is a minor, recoverable inconsistency.

### Restore

Restore into the same Home Assistant (or a test machine) in this order:

1. **Postiz PostgreSQL** (Settings > System > Backups > backup > Restore >
   select only this app). Wait for `ready to accept connections`.
2. **Postiz Redis** and **Postiz Temporal**.
3. **Postiz**.

A full-backup restore restores everything at once; the apps then wait for
each other on start. Restoring an app replaces its current data folder with
the backup copy.

Before any upgrade, take a manual backup that includes at least Postiz
PostgreSQL and Postiz (see Part 12).

---

## Part 12 - Updating

Nothing updates by itself: every image is pinned to an exact version and the
apps only change when **you** bump `version` in a `config.yaml` and push. Home
Assistant then offers an **Update** for that app; updating keeps its data.

### Update checklist (when a new Postiz release appears)

1. Read the Postiz release notes (<https://github.com/gitroomhq/postiz-app/releases>),
   especially "breaking", "Prisma", "Temporal" and env-variable changes.
2. Look at the current official compose file:
   <https://github.com/gitroomhq/postiz-docker-compose/blob/main/docker-compose.yaml>.
3. Compare image versions (PostgreSQL, Redis, Temporal, UI) with the table at
   the top of this README.
4. Compare environment variables with
   <https://docs.postiz.com/configuration/reference> and with what
   `postiz/rootfs/usr/local/bin/postiz-run.sh` sets.
5. Check database changes: Postiz applies schema changes with
   `prisma db push --accept-data-loss` **on every start**; there are no
   migrations you can roll back.
6. Check Temporal changes (new server version? new search attributes?).
7. Check database requirements (PostgreSQL / Redis minimums).
8. Edit the `FROM` line and the `upstream_version` comments, bump `version` in
   that app's `config.yaml`, add a `CHANGELOG.md` entry.
9. **Take a Home Assistant backup** (PostgreSQL + Postiz at least), push,
   update the app in Home Assistant, run the relevant tests from
   [docs/TEST-PLAN.md](docs/TEST-PLAN.md).

Dependabot (`.github/dependabot.yml`) opens pull requests for new base-image
tags so you notice them; it never merges or deploys anything.

### Rules that prevent upgrade traps

- **Postiz downgrades are not a rollback.** `db push --accept-data-loss` makes
  the database match the running version and can drop columns a newer version
  added. To roll back, restore the backup taken before the update (PostgreSQL
  **and** Postiz apps).
- **PostgreSQL major versions** (16 → 17) need a dump/restore. The app refuses
  to start on a data folder from another major version and says so. Minor
  updates (16.15 → 16.16) are safe.
- **Temporal**: one minor version at a time (1.28 → 1.29), each started once;
  the schema upgrade runs automatically. The auto-setup image is deprecated
  after 1.29, so going further will need a reworked Temporal app.
- **Do not change the Debian variant** of the PostgreSQL image (trixie) -
  collation rules can change between C libraries.

### Switching to prebuilt images (recommended after testing)

Locally built apps put their image into every backup (see Part 11). To avoid
that:

1. GitHub > your repo > Actions > **Build images** > Run workflow (builds all
   five wrappers for amd64 and pushes them to `ghcr.io/<you>/postiz-ha-<slug>`
   tagged with each app's `version`).
2. GitHub > Packages: make each package public (or add GHCR credentials under
   Settings > Apps > ⋮ > Registries in Home Assistant).
3. In each `config.yaml` add, e.g. for Postiz:
   `image: ghcr.io/<you>/postiz-ha-postiz` (lowercase, no tag), bump
   `version`, push, run the workflow again for the new version, then
   **Update** the apps in Home Assistant.

From then on the workflow must be run for every new `version` before you
update the app.

---

## Part 13 - Troubleshooting

Use each app's **Log** tab first (Settings > Apps > app > Log). Supervisor's
own log is under Settings > System > Logs > Supervisor. You should not need
`docker` commands; the `ha` CLI in the Terminal app works too, e.g.
`ha apps logs <repo-prefix>_postiz` (on older CLI versions: `ha addons logs`).

| Symptom | Likely cause | Check / fix |
|---|---|---|
| Postiz: "PostgreSQL ... did not become ready" / "does not resolve" | PostgreSQL app not started, or installed from a different repository | Start **Postiz PostgreSQL**; check its log for FATAL lines; all apps must come from the same repository |
| Postiz: "PostgreSQL rejected the password for user 'postiz'" | `database_password` ≠ `postiz_password` | Make them identical; restart PostgreSQL first, then Postiz |
| Temporal: "rejected the password for user 'temporal'" | `database_password` ≠ `temporal_password` | Same as above |
| "Redis connection refused" / "Redis rejected the password" | Redis app stopped or passwords differ | Start **Postiz Redis**; compare `password` and `redis_password` |
| "Temporal ... did not report namespace 'default'" | Temporal still starting, or failing on the DB | Read the Temporal log: password errors, PostgreSQL not ready; first start takes longer |
| PostgreSQL: "data ... was created by PostgreSQL NN" | The data folder came from another major version | Restore the matching app version from backup; see PostgreSQL DOCS |
| Web UI does not load at `:4007` | Postiz still starting (first start takes minutes), port changed, or app stopped | Wait for `Postiz is ready`; check Postiz > Network shows 4007; check the log for errors |
| Login succeeds but you land on the login page again | Browser address ≠ `external_url`, or HTTPS URL configured while browsing via HTTP | Browse to exactly the External URL; for plain HTTP the URL must start with `http://` (the app then sets NOT_SECURED) |
| OAuth redirects to `localhost` or the wrong host | `external_url` not set to the public URL | Set External URL to your HTTPS hostname, restart, update the redirect URI at the provider |
| External OAuth callback fails | Redirect URI at the provider doesn't match `<External URL>/integrations/social/<provider>`; provider requires HTTPS; proxy blocks the callback | Compare URIs character by character; use HTTPS; check the proxy log |
| Images upload but don't display | Uploaded under a different `external_url`; proxy doesn't pass `/uploads/` | Uploads use the URL configured at upload time; re-upload after changing the URL; test `<External URL>/uploads/...` directly |
| Scheduled posts never execute | Temporal down or not ready; channel token expired; provider queue excluded | Temporal log; Temporal UI → `post_<id>` workflow and its error; remove the provider from `exclude_queues` |
| Postiz restarts repeatedly | Dependency missing after `wait_timeout`, `prisma db push` failure (no internet / DB error), out of memory | Log just before the restart; Watchdog gives up after 5 attempts |
| HA reports an app unhealthy / watchdog restarts it | Port not answering for >4 min (2 watchdog checks) | Its log; for Postiz the check is TCP only, so it means nginx is down |
| "Database starts after Postiz" | Normal during boot or manual starts | Postiz waits up to `wait_timeout` (900 s) for PostgreSQL, Redis and Temporal; nothing to fix unless it times out |
| Temporal log shows `level=ERROR ... connection refused` at start | Upstream script polling the server it just started | Expected; only a problem if `Temporal is ready` never appears |
| Disk filling up | Media, HA backups containing the 5 GB Postiz image | Check Settings > System > Storage; reduce backup retention; switch to prebuilt images |

Emergency only (normally never needed): the "Advanced SSH & Web Terminal"
app with protection mode off can run `docker` commands against the host. Doing
so bypasses Supervisor; avoid it unless you are recovering from a failure.

---

## Part 14 - Rollback / complete removal

This touches only the Postiz apps. It does not modify `configuration.yaml`, the
recorder database, other apps, Supervisor or HAOS partitions.

> ⚠️ **Uninstalling an app permanently deletes its data folder.** For Postiz
> PostgreSQL that means all Postiz accounts, posts and channels; for Postiz it
> means your uploaded media. Take a backup first if you might want them back
> (Settings > System > Backups > Create backup > select the Postiz apps).

1. **Stop** Postiz (and Temporal UI if running).
2. **Stop** Postiz Temporal, then Postiz Redis, then Postiz PostgreSQL.
3. **Uninstall** each app (Postiz, Temporal UI, Postiz Temporal, Postiz Redis,
   Postiz PostgreSQL). For the Postiz app the dialog offers "Also delete the
   app's configuration folder" - tick it to remove `postiz.env` too; otherwise
   that folder stays under `addon_configs`.
4. **Remove the repository**: Settings > Apps > App store > ⋮ > Repositories >
   remove it.
5. Reboot only if you want to; it is not required.
6. Check Home Assistant: Settings > System > Repairs (nothing new),
   Settings > System > Storage (space reclaimed after images are removed).

Uninstalling removes the app images too. Old backups that include the apps
remain until you delete them.

---

## Part 15 - Known limitations

- **amd64 only** in this version.
- **Not tested on real Home Assistant hardware by the author of these files.**
  The PostgreSQL, Redis and Temporal start-up logic and the Postiz wrapper were
  exercised against real PostgreSQL 16, Redis 7 and Temporal 1.28.4 binaries
  outside Home Assistant, and every `config.yaml` was validated with the
  Supervisor's own schema code; the container builds themselves first run on
  your machine. See docs/ARCHITECTURE.md, "Verification".
- **Passwords are entered twice** (server and client app). Supervisor has no
  supported, low-privilege way to share secrets between apps.
- **No Ingress / sidebar panel** for Postiz (Postiz cannot run under a path
  prefix). Use port 4007 or your own HTTPS hostname.
- **No per-app memory limit**: Supervisor has no such option. Apps run with
  a higher OOM score than Home Assistant Core, so the kernel kills an app
  before Core under memory pressure, and you can always stop Postiz from the
  UI. You can cap Node.js heap with `NODE_OPTIONS=--max-old-space-size=...`
  in `postiz.env`.
- **Locally built images are included in backups** (~5 GB for Postiz) until
  you switch to prebuilt images.
- **Backups are per app**, not one coordinated snapshot.
- **Postiz needs internet at start** (`pnpm dlx prisma` may download Prisma).
- **Temporal auto-setup image is deprecated upstream** after 1.29; a future
  version of the Temporal app will need to use `temporalio/server` plus a
  schema job.
- **Temporal UI has no authentication** - start it only while you use it.
- **Redis password and DB passwords** are restricted to `A-Z a-z 0-9 . _ ~ -`
  to stay safe inside URLs and generated config files.
- Postiz's own logs (pm2/nginx files inside the container) are truncated when
  they exceed 20 MB; the app log in Home Assistant is unaffected.
