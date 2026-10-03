# Postiz Redis - thin wrapper around the official Redis image.
#
# upstream_version: redis 7.2.16 (Debian bookworm variant)
# Postiz's official compose uses redis:7.2; Postiz needs Redis >= 6.
FROM redis:8.4.0-bookworm

ARG BUILD_VERSION=dev
ARG BUILD_ARCH=amd64

# jq: read /data/options.json. Nothing else is added.
RUN apt-get update \
    && apt-get install -y --no-install-recommends jq \
    && rm -rf /var/lib/apt/lists/*

COPY rootfs/ /
RUN chmod 0755 /usr/local/bin/postiz-redis-run.sh \
    && chmod 0644 /usr/local/lib/postiz-ha/common.sh

STOPSIGNAL SIGTERM

ENTRYPOINT ["/usr/local/bin/postiz-redis-run.sh"]
CMD []

LABEL \
    io.hass.name="Postiz Redis" \
    io.hass.description="Redis 7.2 for the Postiz app suite" \
    io.hass.type="app" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.version="${BUILD_VERSION}" \
    org.opencontainers.image.source="https://github.com/docker-library/redis"
