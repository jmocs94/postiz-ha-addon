#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Temporal UI for Postiz - start script (optional app).
# Discovers the Postiz Temporal app, then execs the unmodified upstream
# start-ui-server.sh as the image's "temporal" user.
# -----------------------------------------------------------------------------
set -euo pipefail

export POSTIZ_HA_COMPONENT="postiz-temporal-ui"
# shellcheck source=SCRIPTDIR/../lib/postiz-ha/common.sh
source /usr/local/lib/postiz-ha/common.sh

trap 'log "Stop requested during start-up; exiting."; exit 0' TERM INT

OWN_SLUG="postiz_temporal_ui"

log "Starting Temporal UI ${TEMPORAL_UI_UPSTREAM_VERSION:-?} for Postiz."
warn "Temporal UI has NO login of its own. Anyone who can reach this port can see workflow data. Stop this app when you are done debugging."

TEMPORAL_HOST="$(sibling_host "${OWN_SLUG}" postiz_temporal "$(opt temporal_host)")" || exit 1
READ_ONLY="$(opt_bool read_only true)"
WAIT_TIMEOUT="$(opt wait_timeout 600)"
case "${WAIT_TIMEOUT}" in
    '' | *[!0-9]*) die "wait_timeout must be a whole number of seconds." ;;
esac

wait_until "Temporal host name '${TEMPORAL_HOST}' to resolve" "${WAIT_TIMEOUT}" host_resolves "${TEMPORAL_HOST}" \
    || die "'${TEMPORAL_HOST}' does not resolve. Is 'Postiz Temporal' installed from this repository and started?"
wait_until "Temporal gRPC port" "${WAIT_TIMEOUT}" tcp_open "${TEMPORAL_HOST}" 7233 \
    || die "Temporal at ${TEMPORAL_HOST}:7233 is not reachable."

export TEMPORAL_ADDRESS="${TEMPORAL_HOST}:7233"
unset SUPERVISOR_TOKEN HASSIO_TOKEN
export TEMPORAL_UI_PORT="8080"
export TEMPORAL_DEFAULT_NAMESPACE="default"
export TEMPORAL_NOTIFY_ON_NEW_VERSION="false"
# Plain-HTTP LAN access: the CSRF cookie must not be marked Secure.
export TEMPORAL_CSRF_COOKIE_INSECURE="true"
export TEMPORAL_DISABLE_WRITE_ACTIONS="${READ_ONLY}"
if [ "${READ_ONLY}" = "true" ]; then
    log "Read-only mode: terminate/cancel/signal/reset actions are disabled."
fi

log "Temporal UI will listen on container port 8080 (published as configured in the Network section)."
cd /home/ui-server
exec su-exec temporal ./start-ui-server.sh
