# Postiz PostgreSQL - thin wrapper around the official PostgreSQL image.
#
# upstream_version: postgres 16.15 (Debian trixie variant)
# Why 16: Temporal tests PostgreSQL 13-16; Postiz requires >= 14.
# The Debian variant is pinned explicitly because changing the C library
# (bookworm <-> trixie <-> alpine) can change collation behaviour.
# NEVER change the major version (16) without a dump/restore - see DOCS.md.
FROM postgres:16.15-trixie

ARG BUILD_VERSION=dev
ARG BUILD_ARCH=amd64

# jq: read /data/options.json. Nothing else is added.
RUN apt-get update \
    && apt-get install -y --no-install-recommends jq \
    && rm -rf /var/lib/apt/lists/*

COPY rootfs/ /
RUN chmod 0755 /usr/local/bin/postiz-postgres-run.sh \
    && chmod 0644 /usr/local/lib/postiz-ha/common.sh /usr/local/share/postiz-ha/reconcile.sql

# Supervisor's /data volume holds the cluster; the image's own VOLUME path
# (/var/lib/postgresql/data) is not used.
ENV PGDATA=/data/postgres

# Same as upstream: SIGINT = PostgreSQL "fast" shutdown.
STOPSIGNAL SIGINT

ENTRYPOINT ["/usr/local/bin/postiz-postgres-run.sh"]
CMD []

LABEL \
    io.hass.name="Postiz PostgreSQL" \
    io.hass.description="PostgreSQL 16 for the Postiz app suite" \
    io.hass.type="app" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.version="${BUILD_VERSION}" \
    org.opencontainers.image.source="https://github.com/docker-library/postgres"
