# Postiz

Self-hosted [Postiz](https://postiz.com) social media scheduler (official image
`ghcr.io/gitroomhq/postiz-app:v2.25.0`, unmodified).

**Before starting this app**, install and start **Postiz PostgreSQL**,
**Postiz Redis** and **Postiz Temporal** from the same repository. This app
waits for them (up to `wait_timeout` seconds) and stops with a clear error if
one is missing or a password does not match.

## Required options

| Option | What to enter |
|---|---|
| `external_url` | The exact address you open Postiz with, **no path**: `http://192.168.55.65:4007` for local testing, later e.g. `https://postiz.example.com`. |
| `database_password` | Same value as `postiz_password` in **Postiz PostgreSQL**. |
| `redis_password` | Same value as `password` in **Postiz Redis**. |

Everything else is optional.

### How the URL settings are derived

From `external_url` the app sets:

| Postiz variable | Value |
|---|---|
| `MAIN_URL`, `FRONTEND_URL` | `external_url` |
| `NEXT_PUBLIC_BACKEND_URL` | `external_url` + `/api` |
| `BACKEND_INTERNAL_URL` | `http://localhost:3000` (backend inside this container) |
| `NOT_SECURED` | `true` only when `external_url` starts with `http://` |

`NOT_SECURED` is needed for plain HTTP: otherwise Postiz marks its login
cookie `Secure`, the browser drops it and the login page loops. With an
`https://` URL secure cookies are used.

Use the address you actually type in the browser. If `external_url` says
`192.168.55.65` but you browse to `homeassistant.local`, login will not work.

Changing `external_url` only needs a restart. **But:** Postiz stores the full
URL of each local upload in its database, so media uploaded under the old URL
keeps the old address. Set your final HTTPS URL before you upload media you
want to keep.

## Other options

| Option | Default | Notes |
|---|---|---|
| `jwt_secret` | empty | Empty = a random secret generated once on first start and kept in `/data/secrets/jwt_secret`. Changing it signs everybody out. |
| `disable_registration` | `true` | With `true`, Postiz still lets the **first** account register (verified in Postiz source); after that sign-up is closed. Generic OIDC (if you configure it in `postiz.env`) can still create accounts. |
| `storage_provider` | `local` | `local` = files in this app's data folder (in backups). `cloudflare` = R2, fill in the `cloudflare_*` options. |
| `email_provider` | `none` | `none`: new accounts are activated without e-mail. `resend` needs `resend_api_key`. `nodemailer` needs `smtp_host` (+ port/user/password/secure). Set `email_from_name` and `email_from_address` for either. **With a provider set, new local accounts must confirm by e-mail** - make sure sending works first. |
| `wait_timeout` | 900 | Seconds to wait for each dependency at start-up. |
| `openai_api_key` | | Enables AI features. |
| `api_limit` | Postiz default (90) | Public API requests per hour. |
| `exclude_queues` | | Comma-separated provider queues for which no worker runs (e.g. `dribbble,lemmy`). Posting to an excluded provider will not work. |
| `postgres_host`, `redis_host`, `temporal_host` | | Leave empty; only for when automatic discovery fails. |

## Social providers

Fill in only the providers you use; leave the rest empty. The redirect /
callback URL to register with each provider is
`<external_url>/integrations/social/<provider>` (verified in the Postiz
provider source for v2.25.0):

| Provider | Options | Callback URL path |
|---|---|---|
| X | `x_api_key`, `x_api_secret` | `/integrations/social/x` |
| LinkedIn | `linkedin_client_id`, `linkedin_client_secret` | `/integrations/social/linkedin` |
| LinkedIn Page | (same LinkedIn keys) | `/integrations/social/linkedin-page` |
| Reddit | `reddit_client_id`, `reddit_client_secret` | `/integrations/social/reddit` |
| Facebook | `facebook_app_id`, `facebook_app_secret` | `/integrations/social/facebook` |
| Instagram (via Facebook Business) | (Facebook keys) | `/integrations/social/instagram` |
| Instagram (standalone) | `instagram_app_id`, `instagram_app_secret` | `/integrations/social/instagram-standalone` |
| Threads | `threads_app_id`, `threads_app_secret` | `/integrations/social/threads` |
| YouTube | `youtube_client_id`, `youtube_client_secret` | `/integrations/social/youtube` |
| TikTok | `tiktok_client_id`, `tiktok_client_secret` | `/integrations/social/tiktok` |
| Pinterest | `pinterest_client_id`, `pinterest_client_secret` | `/integrations/social/pinterest` |
| Discord | `discord_client_id`, `discord_client_secret`, `discord_bot_token_id` | `/integrations/social/discord` |
| Mastodon | `mastodon_url`, `mastodon_client_id`, `mastodon_client_secret` | `/integrations/social/mastodon` |
| Bluesky | none (handle + app password in the Postiz UI) | - |

Other providers (GitHub, Slack, Telegram, Dribbble, Beehiiv, TikTok Business,
generic OIDC, ...) go into `postiz.env` (below). Provider setup guides:
<https://docs.postiz.com/providers/overview>.

**HTTPS:** most providers (Meta, LinkedIn, TikTok, YouTube...) require an
HTTPS redirect URI and a publicly reachable URL. Postiz itself routes the
Instagram-standalone, Threads, TikTok and Slack redirects through
`redirectmeto.com` when `external_url` is not HTTPS. TikTok and Instagram also
download your media from Postiz's public URL. Plan on an HTTPS hostname before
connecting real channels; local `http://` is fine for installing and testing.

## postiz.env (advanced)

This app maps its own config folder to `/config`. On first start it creates
`postiz.env` there with every line commented out. In Home Assistant you find it
in the **addon_configs** share (called **app_configs** on newer Samba app versions) or from the Advanced SSH & Web Terminal app (`/addon_configs/...`), in the folder
ending in `_postiz`.

- One `KEY=VALUE` per line, `#` comments. Values are used literally (no
  `$VAR` expansion, no commands are run); surrounding quotes are removed.
- Keys this app manages (`DATABASE_URL`, `REDIS_URL`, `TEMPORAL_ADDRESS`,
  `JWT_SECRET`, `FRONTEND_URL`, `MAIN_URL`, `NEXT_PUBLIC_BACKEND_URL`,
  `BACKEND_INTERNAL_URL`, `UPLOAD_DIRECTORY`, `NOT_SECURED`,
  `STORAGE_PROVIDER`, `DISABLE_REGISTRATION`, ...) are ignored with a warning.
- If a setting is set both here and on the Configuration tab, the
  Configuration tab wins.
- The log lists the variable **names** loaded from the file (never values).
- Restart the app after editing.

Note: the current Postiz image does **not** read `/config/postiz.env` on its
own (older Postiz docs say it does); this app's start script loads it.

## Data

| Path in container | Contents | In HA backup |
|---|---|---|
| `/data/uploads` | Uploaded media (`/uploads/...` is served by Postiz's nginx from here) | yes |
| `/data/secrets/jwt_secret` | Auto-generated JWT secret | yes |
| `/config/postiz.env` | Optional extra variables | yes |

Everything else (accounts, posts, channels) is in the **Postiz PostgreSQL**
app. Expect the uploads folder to grow with your media; images are usually
0.1-5 MB each, videos much more.

## Start-up log

```
[postiz] External URL: http://192.168.55.65:4007 (plain HTTP: NOT_SECURED=true ...)
[postiz] JWT secret: generated a new random secret (first start) ...
[postiz] PostgreSQL login as 'postiz' verified.
[postiz] Redis PING/PONG with authentication verified.
[postiz] Temporal (namespace 'default') ready (after 0s).
[postiz] Starting Postiz: prisma db push (schema sync), then backend, frontend and orchestrator under pm2.
... Postiz's own output ...
[postiz] Postiz is ready: backend and frontend answer on port 5000. Open http://192.168.55.65:4007
```

The first start takes longer (schema creation, Next.js warm-up); a few
minutes is normal. `prisma db push` downloads the Prisma CLI from the npm
registry when it is not cached, so this app needs internet access at start.

## Ingress

Not supported, on purpose: Postiz has no base-path support and uses absolute
redirects and cookies, and OAuth needs a stable public URL. Use
**Open web UI** (port 4007) or your own HTTPS hostname.
