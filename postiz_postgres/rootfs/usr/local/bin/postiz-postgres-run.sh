#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Postiz PostgreSQL app - start script.
#
# Phase 1 (root):     read /data/options.json, validate, prepare /data/postgres,
#                     then re-exec this script as the "postgres" user via gosu
#                     (the same step-down the official image performs).
# Phase 2 (postgres): reuse the official image's docker-entrypoint.sh functions
#                     to initialise an empty cluster, rewrite pg_hba.conf,
#                     reconcile roles/databases on a socket-only temporary
#                     server, then `exec postgres` as PID 1 (init: false).
#
# Signals: postgres is PID 1 and the image STOPSIGNAL is SIGINT (fast
# shutdown), exactly like the official image. config.yaml timeout gives it
# 120 s to checkpoint.
# -----------------------------------------------------------------------------
set -euo pipefail

export POSTIZ_HA_COMPONENT="postiz-postgres"
# shellcheck source=SCRIPTDIR/../lib/postiz-ha/common.sh
source /usr/local/lib/postiz-ha/common.sh

: "${PGDATA:=/data/postgres}"
export PGDATA

if [ "$(id -u)" = "0" ]; then
    log "Starting Postiz PostgreSQL app (PostgreSQL ${PG_VERSION:-${PG_MAJOR:-?}})."

    POSTIZ_DB_PASSWORD="$(opt postiz_password)"
    TEMPORAL_DB_PASSWORD="$(opt temporal_password)"
    require_password "Postiz database password" "${POSTIZ_DB_PASSWORD}" "postiz_password"
    require_password "Temporal database password" "${TEMPORAL_DB_PASSWORD}" "temporal_password"
    if [ "${POSTIZ_DB_PASSWORD}" = "${TEMPORAL_DB_PASSWORD}" ]; then
        die "postiz_password and temporal_password must be different."
    fi

    PG_MAX_CONNECTIONS="$(opt max_connections 100)"
    PG_SHARED_BUFFERS_MB="$(opt shared_buffers_mb 128)"
    case "${PG_MAX_CONNECTIONS}${PG_SHARED_BUFFERS_MB}" in
        *[!0-9]*) die "max_connections and shared_buffers_mb must be whole numbers." ;;
    esac
    export POSTIZ_DB_PASSWORD TEMPORAL_DB_PASSWORD PG_MAX_CONNECTIONS PG_SHARED_BUFFERS_MB

    # Refuse to touch a data directory from a different PostgreSQL major
    # version instead of letting the server fail half-way (upgrade trap).
    if [ -s "${PGDATA}/PG_VERSION" ]; then
        existing_major="$(tr -d '[:space:]' < "${PGDATA}/PG_VERSION")"
        if [ "${existing_major}" != "${PG_MAJOR}" ]; then
            die "The data in ${PGDATA} was created by PostgreSQL ${existing_major}, but this app runs PostgreSQL ${PG_MAJOR}. Major upgrades need a dump/restore (see the app documentation). Nothing was changed."
        fi
    fi

    mkdir -p "${PGDATA}" /var/run/postgresql
    chown postgres:postgres "${PGDATA}" /var/run/postgresql
    chmod 0700 "${PGDATA}"
    chmod 03775 /var/run/postgresql
    # Fix ownership only where it is wrong (cheap on an existing cluster).
    find "${PGDATA}" \! -user postgres -exec chown postgres:postgres '{}' +

    exec gosu postgres "$0" "$@"
fi

# ----------------------------- phase 2: postgres -----------------------------

# The official entrypoint is written to be sourced; it then only defines
# functions. It enables `set -Eeo pipefail` itself and is not `set -u` safe.
set +u
# shellcheck source=/dev/null
source /usr/local/bin/docker-entrypoint.sh

export POSTGRES_USER="postgres"
# The superuser is only reachable through the local socket with peer
# authentication (pg_hba below rejects it over TCP), so its password is a
# random value that is never stored or printed.
POSTGRES_PASSWORD="$(head -c 48 /dev/urandom | od -An -tx1 | tr -d ' \n')"
export POSTGRES_PASSWORD
export POSTGRES_DB="postgres"
export POSTGRES_INITDB_ARGS="--auth-local=peer --auth-host=scram-sha-256 --encoding=UTF8 --locale=C.UTF-8 --data-checksums"

docker_setup_env

if [ -z "${DATABASE_ALREADY_EXISTS}" ]; then
    log "Data directory is empty: initialising a new PostgreSQL ${PG_MAJOR} cluster in ${PGDATA} (first start)."
    docker_init_database_dir > /dev/null
    log "Cluster initialised (UTF8, C.UTF-8, data checksums on)."
else
    log "Existing PostgreSQL ${PG_MAJOR} cluster found in ${PGDATA}; reusing it."
fi
unset POSTGRES_PASSWORD

# pg_hba.conf is managed by this app and rewritten on every start.
cat > "${PGDATA}/pg_hba.conf" << 'EOF'
# Managed by the Postiz PostgreSQL Home Assistant app.
# This file is rewritten on every start - local edits are discarded.
#
# TYPE  DATABASE                      USER      ADDRESS  METHOD
local   all                           postgres           peer
host    all                           postgres  all      reject
host    postiz                        postiz    all      scram-sha-256
host    temporal,temporal_visibility  temporal  all      scram-sha-256
host    all                           all       all      reject
EOF
chmod 0600 "${PGDATA}/pg_hba.conf"

log "Reconciling roles and databases (postiz, temporal, temporal_visibility)..."
docker_temp_server_start > /dev/null
PGHOST='' PGHOSTADDR='' psql -X -q --no-psqlrc --username postgres --dbname postgres \
    -f /usr/local/share/postiz-ha/reconcile.sql > /dev/null
docker_temp_server_stop > /dev/null
log "Roles and databases are in place; passwords applied from app options."

unset POSTIZ_DB_PASSWORD TEMPORAL_DB_PASSWORD SUPERVISOR_TOKEN HASSIO_TOKEN

log "Starting PostgreSQL ${PG_MAJOR} on port 5432 (internal Supervisor network only unless you publish the port)."
exec postgres \
    -c listen_addresses='*' \
    -c port=5432 \
    -c max_connections="${PG_MAX_CONNECTIONS}" \
    -c shared_buffers="${PG_SHARED_BUFFERS_MB}MB" \
    -c password_encryption=scram-sha-256 \
    -c log_line_prefix='%m [%p] %q%u@%d ' \
    -c log_min_duration_statement=-1
