# Temporal UI for Postiz - thin wrapper around temporalio/ui (optional app).
#
# upstream_version: temporalio/ui 2.34.0 (same as Postiz's official compose)
FROM temporalio/ui:2.55.0

ARG BUILD_VERSION=dev
ARG BUILD_ARCH=amd64

ENV TEMPORAL_UI_UPSTREAM_VERSION=2.34.0

# Root only for the start script, which drops to the image user with su-exec.
# hadolint ignore=DL3002,DL3066
USER root
RUN apk add --no-cache jq su-exec

COPY rootfs/ /
RUN chmod 0755 /usr/local/bin/postiz-temporal-ui-run.sh \
    && chmod 0644 /usr/local/lib/postiz-ha/common.sh

WORKDIR /home/ui-server
ENTRYPOINT ["/usr/local/bin/postiz-temporal-ui-run.sh"]
CMD []

LABEL \
    io.hass.name="Temporal UI for Postiz" \
    io.hass.description="Optional Temporal web UI for debugging Postiz workflows" \
    io.hass.type="app" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.version="${BUILD_VERSION}" \
    org.opencontainers.image.source="https://github.com/temporalio/ui-server"
