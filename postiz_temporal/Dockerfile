# Postiz Temporal - thin wrapper around temporalio/auto-setup.
#
# upstream_version: temporalio/auto-setup 1.28.4
# Postiz's official compose pins 1.28.1; 1.28.4 is the latest patch of the same
# minor line (security fixes, identical schema and config template).
# NOTE: Temporal deprecated the auto-setup image after the 1.29 line. Moving
# beyond 1.29 means switching to temporalio/server + admin-tools schema jobs.
FROM temporalio/auto-setup:1.28.4

ARG BUILD_VERSION=dev
ARG BUILD_ARCH=amd64

ENV TEMPORAL_UPSTREAM_VERSION=1.28.4

# The upstream image runs as "temporal" (uid 1000). We need root briefly to
# read /data/options.json, then step down with su-exec.
# hadolint ignore=DL3002,DL3066
USER root

# jq: read options; su-exec: drop privileges; postgresql-client: pg_isready
# and a login check that gives a clear error for a wrong password.
RUN apk add --no-cache jq su-exec postgresql16-client

COPY rootfs/ /
# COPY resets ownership of directories that already exist in the image
# (/etc/temporal/config is owned by "temporal" upstream). The upstream
# entrypoint renders /etc/temporal/config/docker.yaml as the "temporal" user,
# so give the config directories back to it.
RUN chmod 0755 /usr/local/bin/postiz-temporal-run.sh \
    && chmod 0644 /usr/local/lib/postiz-ha/common.sh \
       /etc/temporal/config/dynamicconfig/postiz.yaml \
    && chown temporal:temporal /etc/temporal/config /etc/temporal/config/dynamicconfig

WORKDIR /etc/temporal
ENTRYPOINT ["/usr/local/bin/postiz-temporal-run.sh"]
CMD []

LABEL \
    io.hass.name="Postiz Temporal" \
    io.hass.description="Temporal workflow server for Postiz" \
    io.hass.type="app" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.version="${BUILD_VERSION}" \
    org.opencontainers.image.source="https://github.com/temporalio/docker-builds"
