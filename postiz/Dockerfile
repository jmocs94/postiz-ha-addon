# Postiz - thin wrapper around the official prebuilt Postiz image.
#
# upstream_version: ghcr.io/gitroomhq/postiz-app:v2.25.0
# The upstream image is built from postiz-app/Dockerfile.dev:
#   base node:22.20-bookworm-slim, WORKDIR /app, runs as root,
#   no ENTRYPOINT, CMD ["sh", "-c", "nginx && pnpm run pm2"].
# Nothing in /app is modified; the start script runs the same sequence.
FROM ghcr.io/gitroomhq/postiz-app:v2.25.0

ARG BUILD_VERSION=dev
ARG BUILD_ARCH=amd64

ENV POSTIZ_UPSTREAM_VERSION=v2.25.0

# jq: read options; curl: Temporal/HTTP checks; postgresql-client: pg_isready
# and login check; redis-tools: authenticated PING. All from Debian bookworm.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl jq postgresql-client redis-tools \
    && rm -rf /var/lib/apt/lists/*

# Upstream nginx.conf hardcodes "location /uploads/ { alias /uploads/; }".
# Point /uploads at the persistent app data folder.
RUN rm -rf /uploads && ln -s /data/uploads /uploads

COPY rootfs/ /
RUN chmod 0755 /usr/local/bin/postiz-run.sh \
    && chmod 0644 /usr/local/lib/postiz-ha/common.sh \
       /usr/local/share/postiz-ha/postiz.env.example

WORKDIR /app
ENTRYPOINT ["/usr/local/bin/postiz-run.sh"]
CMD []

LABEL \
    io.hass.name="Postiz" \
    io.hass.description="Postiz social media scheduler" \
    io.hass.type="app" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.version="${BUILD_VERSION}" \
    org.opencontainers.image.source="https://github.com/gitroomhq/postiz-app"
