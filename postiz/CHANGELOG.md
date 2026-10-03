# Changelog

## 0.1.0

- First release. Upstream: ghcr.io/gitroomhq/postiz-app:v2.25.0.
- One canonical `external_url` drives MAIN_URL / FRONTEND_URL / NEXT_PUBLIC_BACKEND_URL.
- NOT_SECURED set automatically for plain-HTTP URLs.
- JWT secret generated once and stored in /data/secrets.
- Uploads persisted in /data/uploads.
- Optional /config/postiz.env with a safe KEY=VALUE parser.
- Graceful SIGTERM handling (pm2 kill, nginx quit); pm2/nginx log files truncated above 20 MB.
