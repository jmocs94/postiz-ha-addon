#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Postiz Temporal app - start script.
#
# 1. Read options, discover the Postiz PostgreSQL app, wait for it and verify
#    the "temporal" user can log in (clear error if the password is wrong).
# 2. Export the environment the upstream temporalio/auto-setup image expects:
#    PostgreSQL for persistence AND visibility (no Elasticsearch),
#    databases pre-created by the PostgreSQL app (SKIP_DB_CREATE=true),
#    no demo search attributes (SKIP_ADD_CUSTOM_SEARCH_ATTRIBUTES=true) so
#    Postiz's two Text search attributes fit PostgreSQL's 3 Text slots.
# 3. exec the unmodified upstream entrypoint as the image's "temporal" user.
#    It renders config, runs setup-schema/update-schema (idempotent),
#    registers the "default" namespace and execs temporal-server.
#
# Signals: tini (init: true) forwards SIGTERM to temporal-server, which shuts
# down gracefully.
# -----------------------------------------------------------------------------
set -euo pipefail

export POSTIZ_HA_COMPONENT="postiz-temporal"
# shellcheck source=SCRIPTDIR/../lib/postiz-ha/common.sh
source /usr/local/lib/postiz-ha/common.sh

# A stop request while we are still waiting for PostgreSQL is a clean exit.
trap 'log "Stop requested during start-up; exiting."; exit 0' TERM INT

OWN_SLUG="postiz_temporal"

log "Starting Postiz Temporal app (Temporal server ${TEMPORAL_UPSTREAM_VERSION:-?}, SQL visibility, no Elasticsearch)."

DB_PASSWORD="$(opt database_password)"
require_password "Temporal database password" "${DB_PASSWORD}" "database_password"

RETENTION="$(opt namespace_retention 72h)"
if ! printf '%s' "${RETENTION}" | grep -Eq '^[0-9]{1,5}h$'; then
    die "namespace_retention must look like 72h (hours)."
fi
LOG_LEVEL_OPT="$(opt log_level warn)"
case "${LOG_LEVEL_OPT}" in
    debug | info | warn | error) ;;
    *) die "log_level must be one of debug, info, warn, error." ;;
esac
WAIT_TIMEOUT="$(opt wait_timeout 600)"
case "${WAIT_TIMEOUT}" in
    '' | *[!0-9]*) die "wait_timeout must be a whole number of seconds." ;;
esac

PG_HOST="$(sibling_host "${OWN_SLUG}" postiz_postgres "$(opt postgres_host)")" || exit 1
log "This app's hostname: $(self_hostname). PostgreSQL app expected at: ${PG_HOST}:5432"

if ! wait_until "PostgreSQL host name '${PG_HOST}' to resolve" "${WAIT_TIMEOUT}" host_resolves "${PG_HOST}"; then
    die "'${PG_HOST}' does not resolve. Is the 'Postiz PostgreSQL' app installed from this same repository and started? (You can set 'postgres_host' to override.)"
fi
if ! wait_until "PostgreSQL to accept connections" "${WAIT_TIMEOUT}" \
    pg_isready -q -h "${PG_HOST}" -p 5432 -d temporal -U temporal -t 3; then
    die "PostgreSQL at ${PG_HOST}:5432 did not become ready within ${WAIT_TIMEOUT}s. Check the 'Postiz PostgreSQL' app log."
fi

check_login() {
    PGPASSWORD="${DB_PASSWORD}" PGCONNECT_TIMEOUT=5 psql -X -q -h "${PG_HOST}" -p 5432 \
        -U temporal -d temporal -tAc 'SELECT 1' 2>&1
}
login_ok=false
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if out="$(check_login)"; then
        login_ok=true
        break
    fi
    case "${out}" in
        *"password authentication failed"*)
            die "PostgreSQL rejected the password for user 'temporal'. 'database_password' here must equal 'temporal_password' in the Postiz PostgreSQL app (then restart that app first, then this one)."
            ;;
    esac
    sleep 3
done
[ "${login_ok}" = "true" ] || die "Could not log in to PostgreSQL as 'temporal' (database 'temporal'). Check the Postiz PostgreSQL app log."
log "PostgreSQL reachable; login as 'temporal' verified."

# The container's own IPv4 address, used as Temporal's membership broadcast
# address. Docker writes it to /etc/hosts next to the Supervisor-assigned
# hostname.
SELF_IP="$(awk -v h="$(self_hostname)" '$1 ~ /^[0-9]+(\.[0-9]+){3}$/ { for (i = 2; i <= NF; i++) if ($i == h) { print $1; exit } }' /etc/hosts)"

# ---- environment for the upstream auto-setup entrypoint ----
export DB="postgres12"
export DB_PORT="5432"
export POSTGRES_SEEDS="${PG_HOST}"
export POSTGRES_USER="temporal"
export POSTGRES_PWD="${DB_PASSWORD}"
export DBNAME="temporal"
export VISIBILITY_DBNAME="temporal_visibility"
export SKIP_DB_CREATE="true"
export SKIP_SCHEMA_SETUP="false"
export ENABLE_ES="false"
export SKIP_ADD_CUSTOM_SEARCH_ATTRIBUTES="true"
export SKIP_DEFAULT_NAMESPACE_CREATION="false"
export DEFAULT_NAMESPACE="default"
export DEFAULT_NAMESPACE_RETENTION="${RETENTION}"
export DYNAMIC_CONFIG_FILE_PATH="/etc/temporal/config/dynamicconfig/postiz.yaml"
export LOG_LEVEL="${LOG_LEVEL_OPT}"
export NUM_HISTORY_SHARDS="4"
# Listen on all interfaces (IPv4 and, when available, IPv6) so siblings can
# connect whichever address family their resolver returns.
export BIND_ON_IP="::0"
if [ -n "${SELF_IP}" ]; then
    export TEMPORAL_BROADCAST_ADDRESS="${SELF_IP}"
fi
# Address the bundled temporal CLI (used by auto-setup) talks to.
export TEMPORAL_ADDRESS="127.0.0.1:7233"
unset DB_PASSWORD
# Temporal never talks to the Supervisor; don't hand it the API token.
unset SUPERVISOR_TOKEN HASSIO_TOKEN

log "Schema check/upgrade and 'default' namespace registration (retention ${RETENTION}) are handled by the upstream auto-setup script."
log "First start prints a long list of schema statements; later starts skip them."

# Announce readiness once, without flooding the log. Double fork so the
# watcher is re-parented to tini (PID 1, init: true), which reaps it when it
# exits instead of leaving a zombie under temporal-server.
(
    (
        deadline=$(($(date +%s) + WAIT_TIMEOUT))
        while [ "$(date +%s)" -lt "${deadline}" ]; do
            if temporal operator namespace describe -n default --address 127.0.0.1:7233 > /dev/null 2>&1; then
                log "Temporal is ready: frontend on port 7233, namespace 'default' available."
                exit 0
            fi
            sleep 5
        done
        warn "Temporal did not report namespace 'default' within ${WAIT_TIMEOUT}s; see messages above."
    ) &
)

cd /etc/temporal
exec su-exec temporal /etc/temporal/entrypoint.sh autosetup
