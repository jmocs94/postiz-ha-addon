# Architecture, research findings and design decisions

Research date: 2026-10-02. Labels: **[DOC]** documented upstream,
**[SRC]** verified in upstream source code, **[TEST]** verified by running it,
**[ASSUMPTION]** reasonable but unverified.

## Part 1 - Upstream findings

### Postiz

| Item | Finding |
|---|---|
| Release | **v2.25.0** (2026-10-02); previous v2.24.0 (2026-09-22). Image build for v2.25.0 succeeded in CI. [SRC] |
| Image | `ghcr.io/gitroomhq/postiz-app:<tag>` (multi-arch manifest; `-amd64`/`-arm64` tags too), built from `Dockerfile.dev`. [SRC] |
| Image internals | base `node:22.20-bookworm-slim`; `WORKDIR /app`; root user; no ENTRYPOINT; `CMD ["sh","-c","nginx && pnpm run pm2"]`. [SRC] |
| Ports | nginx **:5000** → `/api/` → backend :3000, `/uploads/` → `alias /uploads/` (hardcoded), `/` → Next.js :4200. Orchestrator (Temporal workers) :3002. Compose publishes 4007→5000. [SRC] |
| Start sequence | `pm2 delete all; pnpm dlx prisma@6.5.0 db push --accept-data-loss; pm2 start backend/frontend/orchestrator; pm2 logs`. Schema sync on **every** start, no migrations. [SRC] |
| Size | ~5 GB image ([#950](https://github.com/gitroomhq/postiz-app/issues/950)). [DOC] |
| `/config/postiz.env` | Docs say it is read; **the current image does not read it** (only real env vars and `/app/.env` via dotenv). [SRC] |
| Uploads | `UPLOAD_DIRECTORY` (must be `/uploads` because nginx hardcodes it), `NEXT_PUBLIC_UPLOAD_STATIC_DIRECTORY=/uploads`. `NEXT_PUBLIC_UPLOAD_DIRECTORY` is no longer referenced. Stored URL = `FRONTEND_URL + /uploads/...`. [SRC] |
| URLs | `MAIN_URL` (falls back to FRONTEND_URL), `FRONTEND_URL`, `NEXT_PUBLIC_BACKEND_URL` (browser → `<url>/api`), `BACKEND_INTERNAL_URL` (`http://localhost:3000` inside the container). Backend URL is read at runtime (force-dynamic layout), not baked at build. [SRC] |
| HTTP vs HTTPS | Without `NOT_SECURED`, auth cookies are `Secure; SameSite=None` → login fails over plain HTTP on a LAN IP. [SRC] |
| `DISABLE_REGISTRATION=true` | Registration allowed while organisation count is 0 → first user can register; generic OIDC always allowed. [SRC] (`apps/backend/src/services/auth/auth.service.ts`) |
| E-mail | Unset `EMAIL_PROVIDER` → empty provider → users auto-activated. [SRC] |
| `RUN_CRON` | Starts the `missing-post-workflow` Temporal workflow. [SRC] |
| Redis | ioredis; throttler storage, OAuth state, upload tickets, caches. No BullMQ. Persistence not required. [SRC] |
| Temporal | `TEMPORAL_ADDRESS` (default `localhost:7233`), `TEMPORAL_NAMESPACE` (default `default`). Registers **Text** search attributes `organizationId`, `postId` at boot and lists workflows with `postId="<id>" AND ExecutionStatus="Running"`. [SRC] |
| Ingress | No Next.js `basePath`; root-relative redirects/assets/cookies → not compatible with a path-prefixed proxy. [SRC] |
| Requirements | PostgreSQL ≥ 14, Redis ≥ 6, Temporal required since v2.12.0. [DOC] |

Official compose ([postiz-docker-compose](https://github.com/gitroomhq/postiz-docker-compose/blob/main/docker-compose.yaml), last change 2026-07-30): `postgres:17-alpine`, `redis:7.2`, `temporalio/auto-setup:1.28.1`, `elasticsearch:7.17.27` (`-Xms256m -Xmx256m`), second `postgres:16` for Temporal, `temporalio/admin-tools`, `temporalio/ui:2.34.0`, Spotlight (debug profile); dynamic config `limit.maxIDLength: 255`, `system.forceSearchAttributesCacheRefreshOnRead: true`.

### Temporal

| Item | Finding |
|---|---|
| Visibility | SQL ("advanced") visibility on PostgreSQL 12+ is supported since server 1.20. Elasticsearch is *recommended* for large workloads only. [DOC] <https://docs.temporal.io/self-hosted-guide/visibility> |
| Limits | PostgreSQL custom search attributes per namespace: Text **3**, Keyword 10, ... [DOC] <https://docs.temporal.io/search-attribute> |
| Text `=` | Translated to `TextNN @@ 'tok'::tsquery` (whitespace tokenisation, no stemming) - exact match for Postiz's cuid IDs. [SRC] [TEST] |
| auto-setup trap | Adds demo attributes `CustomStringField` + `CustomTextField` (2 Text slots) unless `SKIP_ADD_CUSTOM_SEARCH_ATTRIBUTES=true` → Postiz cannot add its two ([#1504](https://github.com/gitroomhq/postiz-app/issues/1504)). [SRC] |
| PostgreSQL versions | Tested 13-16. 17 not listed. [DOC] <https://docs.temporal.io/temporal-service/persistence> |
| Databases | `temporal` + `temporal_visibility` (separate databases needed; both can live on one server). [SRC] |
| auto-setup | Waits for DB, `setup-schema` (skips if present), `update-schema` (auto-upgrade), registers namespace in background after `cluster health` SERVING. Runs as uid 1000. Deprecated upstream; last tags 1.28.4 and 1.29.7. [SRC] [DOC] |
| 1.28.1 → 1.28.4 | Same schema and config template; CVE fixes (CVE-2025-14986/14987, CVE-2026-5724). [SRC] |
| Upgrades | One minor version at a time. [DOC] <https://docs.temporal.io/self-hosted-guide/upgrade-server> |
| UI | Not required to run Temporal. [DOC] |

### Home Assistant (Supervisor 2026.09.3, HAOS 18.3, verified on your system)

| Item | Finding |
|---|---|
| Naming | Add-ons are now "apps"; `/docs/add-ons/*` redirects to `/docs/apps/*`. [DOC] |
| Hostnames | `{REPO}_{SLUG}` with `_`→`-` (every underscore). `{REPO}` = `local` or `sha1(url.lower())[:8]`. No slug-only alias. Container `Hostname` is set to it. [DOC] [SRC] `supervisor/apps/model.py`, `docker/manager.py`, `store/utils.py` |
| Supervisor API | `/addons/self/info` works without `hassio_api`. Other apps' `options` are redacted unless the caller has `manager`/`admin`. [SRC] |
| Builds | Since 2026.04.0 no default `BUILD_FROM`; use explicit `FROM`. `build.yaml` deprecated. Locally built images are labelled by Supervisor. [DOC] |
| Backups | `/data` + app_config folder + options; **`image.tar` for locally built apps**; `cold` stops the app. Restore replaces data. [SRC] |
| Uninstall | `/data` always deleted; app_config folder only if requested. [SRC] |
| Resources | **No memory/CPU limit option**; apps get `oom_score_adj=200`. [SRC] |
| Watchdog | User toggle (default off); checks every 120 s, restarts after 2 failures; max 5 attempts with backoff per incident. [SRC] |
| Map types | `app_config` (new name since 2026.07, mounts at `/config`). [SRC] |

## Part 2 - Architecture decision

**Chosen: Approach A + B** - separate Supervisor apps, with the Temporal stack
reduced to what Postiz actually needs.

| Approach | Verdict |
|---|---|
| A. One app per service | **Chosen.** Supervisor owns every container; each has its own lifecycle, logs, backup mode and update path. |
| B. Fewer supporting containers | **Applied.** Elasticsearch removed (SQL visibility, tested). One PostgreSQL 16 server hosts `postiz`, `temporal`, `temporal_visibility` with separate users. No admin-tools, no Spotlight, no pgAdmin/RedisInsight. Temporal UI optional with manual start. |
| C. One monolithic container (s6) | Rejected: one update or crash affects everything, PostgreSQL and Temporal upgrades become coupled with Postiz releases, harder recovery. No technical need for it. |
| D. Nested Docker / socket | Rejected outright: bypasses Supervisor, the exact thing this project avoids. |

### Communication

All apps sit on Supervisor's internal `hassio` bridge network. Each wrapper
reads its own hostname (`/etc/hostname`, set by Supervisor to
`{REPO}-{slug}`), strips its own slug to obtain the repository prefix, and
appends the sibling's slug:

| From | To | Address |
|---|---|---|
| Postiz | PostgreSQL | `postgresql://postiz:…@{REPO}-postiz-postgres:5432/postiz` |
| Postiz | Redis | `redis://:…@{REPO}-postiz-redis:6379` |
| Postiz | Temporal | `{REPO}-postiz-temporal:7233` (readiness via HTTP API :7243) |
| Temporal | PostgreSQL | `{REPO}-postiz-postgres:5432` (`temporal`, `temporal_visibility`) |
| Temporal UI | Temporal | `{REPO}-postiz-temporal:7233` |

Fallback: `/addons/self/info` (no extra permissions). Last resort: per-app
host override options. All servers listen dual-stack because Supervisor's
network has IPv6 enabled and Docker's DNS can return AAAA records.

### Credentials

There is no low-privilege Supervisor mechanism for sharing secrets between
apps (`services:` only supports mqtt/mysql; reading another app's options
requires the `manager` role; `/share` would expose secrets to every app that
maps it and to Samba). Therefore: the user sets three passwords, each in the
server and the client app. The PostgreSQL app re-applies passwords on every
start (so changing them is a restart, not a migration). The JWT secret is
generated once in `/data/secrets` (stable across restarts/updates; included in
backups). The PostgreSQL superuser password is random, never stored, and the
superuser is rejected over TCP.

### Permissions per app

No app requests `hassio_api`, `hassio_role`, `homeassistant_api`, `auth_api`,
`docker_api`, `privileged`, `full_access`, `host_*`, devices, or AppArmor
changes. Only Postiz maps a folder (`app_config`, its own). Supervisor's
`/addons/self/info` fallback works without `hassio_api`.

## Part 3 - Resource estimate (not measured on your hardware)

| Component | RAM (typical) | Basis |
|---|---|---|
| Postiz | 0.9-1.5 GB | community reports ~0.9 GB idle; 3 Node processes + workers |
| PostgreSQL 16 | 0.1-0.2 GB | 128 MB shared_buffers + ~40-60 connections |
| Redis | < 30 MB (cap 128 MB) | tiny data set |
| Temporal 1.28.4 | 0.15-0.3 GB | **120 MB measured idle** [TEST]; more with Postiz's workers polling |
| Temporal UI (optional) | ~50 MB | |
| Elasticsearch (removed) | 0.33-0.55 GB saved | 256 MB heap + JVM overhead |
| **Total** | **≈ 1.2-2.0 GB** | peaks maybe 2.5 GB |

Your system: 16 GB RAM, ~2.3 GB used by current apps. Comfortable.
CPU: Temporal and 30-odd idle Postiz workers poll continuously; expect a few
percent of one core at idle on an i5-9500T.

## Part 4 - Risk assessment

| Risk | Mitigation in this repo |
|---|---|
| Memory pressure | No Elasticsearch; Redis capped; PostgreSQL small defaults; apps OOM-killed before HA Core (oom_score_adj 200); optional `NODE_OPTIONS` heap cap; `exclude_queues`. |
| Disk growth | pm2/nginx log files truncated above 20 MB; Redis persistence off; Temporal retention 72 h; **backups of locally built apps include images (~5 GB Postiz)** → switch to GHCR images. |
| CPU spikes at boot | Temporal and Postiz start after HA Core (`startup: application`). |
| Corrupt database | Cold backups; PostgreSQL PID 1 with SIGINT fast shutdown and 120 s timeout; data checksums; major-version guard; collation-stable `C.UTF-8`, pinned Debian variant. |
| Restart loops | Bounded dependency waits with clear FATALs; Postiz watchdog is TCP-only (slow first start not killed); Supervisor watchdog max 5 attempts. |
| Upgrade traps | Exact image pins; Postiz `db push` downgrade danger documented; PostgreSQL major guard; Temporal one-minor-at-a-time documented. |
| Supervisor expectations | Validated against Supervisor's own config/option schema code; explicit `FROM`; SIGTERM handled (no exit-143 warnings); no host access. |
| Security | Only port 4007 (and optional 8233) published; DB/Redis/Temporal internal; per-database users; superuser socket-only; Redis password; no secrets in logs; env-file parser without eval. |

## Verification performed (outside Home Assistant)

The sandbox used to build this repository could not pull images from
ghcr.io or Docker Hub, so the container builds have not been run. What was
run:

- Every `config.yaml` and `repository.yaml` validated with
  `supervisor.apps.validate.SCHEMA_APP_CONFIG` / store schema, and default and
  sample options with `supervisor.apps.options.AppOptions`, from Supervisor
  source at 2026-10-02 (= 2026.09.3 for these modules). [TEST]
- `postiz-postgres-run.sh` with the official `docker-entrypoint.sh` (PG16) and
  PostgreSQL 16 binaries: first init, idempotent second start, password
  rotation, role isolation, superuser TCP rejection, SIGINT clean shutdown,
  major-version guard, password validation. [TEST]
- `postiz-redis-run.sh` with the official Redis entrypoint: auth on, wrong
  password rejected, config file 0600 owned by redis. [TEST]
- `postiz-temporal-run.sh` with the real auto-setup scripts and Temporal 1.28.4
  binaries against the wrapped PostgreSQL: schema setup, namespace creation,
  readiness message, second start skips setup. Separately: Postiz's
  `organizationId`/`postId` Text search attributes registered, workflows
  started with them, `postId="…" AND ExecutionStatus="Running"` returns exactly
  the right workflow, before and after a restart; HTTP API `GET
  /api/v1/namespaces/default` = 200. [TEST]
- `postiz-run.sh` against those real services with stub `pnpm`/`pm2` and the
  upstream `nginx.conf`: env derivation, env-file safety (no command
  execution, reserved keys ignored), password-mismatch errors, URL validation,
  `/uploads/` served from `/data/uploads`, SIGTERM graceful stop. [TEST]
- Sibling hostname derivation for hash and `local` prefixes. [TEST]
- ShellCheck clean, yamllint clean.

Not verified: the five Docker builds, the real Postiz image starting with
these variables, Supervisor networking/DNS at runtime, and backup/restore on
HAOS. These are covered by docs/TEST-PLAN.md.

## Sources

- Postiz app: <https://github.com/gitroomhq/postiz-app> (main @ 2026-10-02; `Dockerfile.dev`, `package.json`, `var/docker/nginx.conf`, `libraries/nestjs-libraries/src/temporal/*`, `apps/backend/src/services/auth/auth.service.ts`)
- Postiz compose: <https://github.com/gitroomhq/postiz-docker-compose>
- Postiz docs: <https://docs.postiz.com/configuration/reference>, <https://docs.postiz.com/providers/overview>, <https://docs.postiz.com/installation/migration>
- Postiz issues: [#1504](https://github.com/gitroomhq/postiz-app/issues/1504), [#1570](https://github.com/gitroomhq/postiz-app/issues/1570), [#2026](https://github.com/gitroomhq/postiz-app/issues/2026), [#950](https://github.com/gitroomhq/postiz-app/issues/950)
- Temporal: <https://docs.temporal.io/self-hosted-guide/visibility>, <https://docs.temporal.io/search-attribute>, <https://docs.temporal.io/temporal-service/persistence>, <https://docs.temporal.io/self-hosted-guide/upgrade-server>, <https://github.com/temporalio/docker-builds>, <https://github.com/temporalio/temporal/releases/tag/v1.30.1>
- Home Assistant: <https://developers.home-assistant.io/docs/apps/configuration>, <https://developers.home-assistant.io/docs/apps/communication>, <https://developers.home-assistant.io/docs/apps/repository>, <https://developers.home-assistant.io/docs/apps/presentation>, <https://developers.home-assistant.io/blog/2026/04/02/builder-migration>, <https://github.com/home-assistant/supervisor> (2026.09.3)
- Official images: <https://github.com/docker-library/postgres>, <https://github.com/docker-library/redis>, <https://hub.docker.com/r/temporalio/auto-setup>, <https://github.com/temporalio/ui-server>
