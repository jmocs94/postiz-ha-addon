#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Postiz app - start script (thin wrapper around the official Postiz image).
#
# What it does, in order:
#   1. Read /data/options.json and validate it.
#   2. Derive every Postiz URL from ONE canonical external URL.
#   3. Load/generate the JWT secret (generated once, stored in /data/secrets).
#   4. Discover the sibling PostgreSQL / Redis / Temporal apps by hostname.
#   5. Load optional extra variables from /config/postiz.env (safe parser,
#      no eval), then apply Configuration-tab options (they win).
#   6. Wait (bounded) for PostgreSQL, Redis and Temporal, with clear errors.
#   7. Run the SAME start sequence as the upstream image
#      (CMD: sh -c "nginx && pnpm run pm2"): nginx, then `pnpm run pm2`
#      (prisma db push -> backend/frontend/orchestrator under pm2 -> pm2 logs).
#
# Signals: tini (init: true) delivers SIGTERM to this script, which stops
# pm2-managed processes gracefully (`pm2 kill`), stops nginx (`nginx -s quit`)
# and exits. Upstream's plain `sh -c` would simply be killed.
# -----------------------------------------------------------------------------
set -euo pipefail

export POSTIZ_HA_COMPONENT="postiz"
# shellcheck source=SCRIPTDIR/../lib/postiz-ha/common.sh
source /usr/local/lib/postiz-ha/common.sh

# A stop request while we are still waiting for dependencies is a clean exit.
trap 'log "Stop requested during start-up; exiting."; exit 0' TERM INT

OWN_SLUG="postiz"
ENV_FILE="/config/postiz.env"
ENV_EXAMPLE="/usr/local/share/postiz-ha/postiz.env.example"
SECRETS_DIR="/data/secrets"
UPLOADS_DIR="/data/uploads"

log "Starting Postiz app (Postiz ${POSTIZ_UPSTREAM_VERSION:-?})."

# ----------------------------------------------------------------- URL ------
EXTERNAL_URL="$(opt external_url)"
EXTERNAL_URL="${EXTERNAL_URL%/}"
if [ -z "${EXTERNAL_URL}" ]; then
    die "Set 'external_url' on the Configuration tab, e.g. http://192.168.1.10:4007 (the exact address you type in the browser)."
fi
if ! printf '%s' "${EXTERNAL_URL}" | grep -Eq '^https?://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?$'; then
    die "'external_url' must be scheme + host (+ optional port) with no path, e.g. http://192.168.1.10:4007 or https://postiz.example.com. Postiz cannot run under a sub-path."
fi
case "${EXTERNAL_URL}" in
    https://*)
        unset NOT_SECURED || true
        log "External URL: ${EXTERNAL_URL} (HTTPS: secure cookies enabled)."
        ;;
    http://*)
        # Without NOT_SECURED Postiz marks its auth cookie "Secure", browsers
        # drop it over plain HTTP and login loops back to /auth.
        export NOT_SECURED="true"
        log "External URL: ${EXTERNAL_URL} (plain HTTP: NOT_SECURED=true so login works without HTTPS)."
        warn "Most social providers require an HTTPS external URL for OAuth. Switch 'external_url' to your HTTPS hostname before connecting channels."
        ;;
esac

# ------------------------------------------------------------- secrets ------
mkdir -p "${SECRETS_DIR}"
chmod 0700 "${SECRETS_DIR}"
JWT_SECRET_OPT="$(opt jwt_secret)"
if [ -n "${JWT_SECRET_OPT}" ]; then
    if [ "${#JWT_SECRET_OPT}" -lt 32 ]; then
        die "'jwt_secret' must be at least 32 characters (or leave it empty to use the auto-generated secret)."
    fi
    JWT_SECRET="${JWT_SECRET_OPT}"
    log "JWT secret: using the value from the Configuration tab."
else
    if [ ! -s "${SECRETS_DIR}/jwt_secret" ]; then
        (umask 0077 && head -c 48 /dev/urandom | od -An -tx1 | tr -d ' \n' > "${SECRETS_DIR}/jwt_secret.tmp")
        mv "${SECRETS_DIR}/jwt_secret.tmp" "${SECRETS_DIR}/jwt_secret"
        log "JWT secret: generated a new random secret (first start) and stored it in ${SECRETS_DIR}/jwt_secret."
    else
        log "JWT secret: reusing the stored secret from ${SECRETS_DIR}/jwt_secret."
    fi
    chmod 0600 "${SECRETS_DIR}/jwt_secret"
    JWT_SECRET="$(cat "${SECRETS_DIR}/jwt_secret")"
fi
unset JWT_SECRET_OPT

DB_PASSWORD="$(opt database_password)"
require_password "Postiz database password" "${DB_PASSWORD}" "database_password"
REDIS_PASSWORD="$(opt redis_password)"
require_password "Redis password" "${REDIS_PASSWORD}" "redis_password"

WAIT_TIMEOUT="$(opt wait_timeout 900)"
case "${WAIT_TIMEOUT}" in
    '' | *[!0-9]*) die "wait_timeout must be a whole number of seconds." ;;
esac

# ----------------------------------------------------------- discovery ------
PG_HOST="$(sibling_host "${OWN_SLUG}" postiz_postgres "$(opt postgres_host)")" || exit 1
REDIS_HOST="$(sibling_host "${OWN_SLUG}" postiz_redis "$(opt redis_host)")" || exit 1
TEMPORAL_HOST="$(sibling_host "${OWN_SLUG}" postiz_temporal "$(opt temporal_host)")" || exit 1
log "This app's hostname: $(self_hostname)."
log "Expecting PostgreSQL at ${PG_HOST}:5432, Redis at ${REDIS_HOST}:6379, Temporal at ${TEMPORAL_HOST}:7233."

# ------------------------------------------------------------- storage ------
STORAGE_PROVIDER_OPT="$(opt storage_provider local)"
mkdir -p "${UPLOADS_DIR}"
# nginx workers (user "www") serve /uploads/ -> /data/uploads; they need to
# traverse /data (no listing) and read the uploads tree.
chmod o+x /data
chmod 0755 "${UPLOADS_DIR}"
if [ ! -L /uploads ]; then
    # The image already ships this symlink; this only repairs an unexpected
    # state, and never deletes anything.
    if [ -e /uploads ]; then
        mv /uploads "/uploads.unexpected.$(date +%s)"
    fi
    ln -s "${UPLOADS_DIR}" /uploads
fi

# --------------------------------------------------- optional env file ------
RESERVED_KEYS=" DATABASE_URL REDIS_URL TEMPORAL_ADDRESS TEMPORAL_NAMESPACE TEMPORAL_TLS TEMPORAL_API_KEY \
JWT_SECRET FRONTEND_URL MAIN_URL NEXT_PUBLIC_BACKEND_URL BACKEND_INTERNAL_URL UPLOAD_DIRECTORY \
NEXT_PUBLIC_UPLOAD_STATIC_DIRECTORY NEXT_PUBLIC_UPLOAD_DIRECTORY NOT_SECURED IS_GENERAL RUN_CRON \
STORAGE_PROVIDER DISABLE_REGISTRATION PORT ORCHESTRATOR_PORT PATH HOME PWD SHELL USER PM2_HOME \
SUPERVISOR_TOKEN HASSIO_TOKEN POSTIZ_UPSTREAM_VERSION "

is_reserved() {
    case "$1" in
        LD_* | POSTIZ_HA_* | BASH_*) return 0 ;;
    esac
    case "${RESERVED_KEYS}" in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

load_env_file() {
    local file="$1" raw line key value n=0 count=0 names=""
    while IFS= read -r raw || [ -n "${raw}" ]; do
        n=$((n + 1))
        line="${raw%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"
        [ -z "${line}" ] && continue
        case "${line}" in \#*) continue ;; esac
        line="${line#export }"
        if [[ ! "${line}" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
            warn "postiz.env line ${n} ignored (expected KEY=VALUE with an UPPER_CASE key)."
            continue
        fi
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        if [[ "${value}" =~ ^\"(.*)\"$ ]] || [[ "${value}" =~ ^\'(.*)\'$ ]]; then
            value="${BASH_REMATCH[1]}"
        fi
        if is_reserved "${key}"; then
            warn "postiz.env line ${n}: '${key}' is managed by this app and was ignored."
            continue
        fi
        export "${key}=${value}"
        count=$((count + 1))
        names="${names} ${key}"
    done < "${file}"
    if [ "${count}" -gt 0 ]; then
        log "Loaded ${count} variable(s) from postiz.env:${names}"
    else
        log "postiz.env contains no active variables."
    fi
}

if [ -d /config ]; then
    if [ ! -e "${ENV_FILE}" ]; then
        cp "${ENV_EXAMPLE}" "${ENV_FILE}"
        chmod 0600 "${ENV_FILE}"
        log "Created ${ENV_FILE} from the example template (everything in it is commented out)."
    fi
    if [ -f "${ENV_FILE}" ]; then
        load_env_file "${ENV_FILE}"
    fi
fi

# ------------------------------------------- Configuration-tab options ------
# set_from_opt OPTION ENV_NAME: export only when the option is non-empty, so a
# value from postiz.env survives when the Configuration-tab field is blank.
set_from_opt() {
    local value
    value="$(opt "$1")"
    if [ -n "${value}" ]; then
        export "$2=${value}"
    fi
}

# Social providers (names from the Postiz provider source, see DOCS.md).
for pair in \
    x_api_key:X_API_KEY x_api_secret:X_API_SECRET \
    linkedin_client_id:LINKEDIN_CLIENT_ID linkedin_client_secret:LINKEDIN_CLIENT_SECRET \
    reddit_client_id:REDDIT_CLIENT_ID reddit_client_secret:REDDIT_CLIENT_SECRET \
    facebook_app_id:FACEBOOK_APP_ID facebook_app_secret:FACEBOOK_APP_SECRET \
    instagram_app_id:INSTAGRAM_APP_ID instagram_app_secret:INSTAGRAM_APP_SECRET \
    threads_app_id:THREADS_APP_ID threads_app_secret:THREADS_APP_SECRET \
    youtube_client_id:YOUTUBE_CLIENT_ID youtube_client_secret:YOUTUBE_CLIENT_SECRET \
    tiktok_client_id:TIKTOK_CLIENT_ID tiktok_client_secret:TIKTOK_CLIENT_SECRET \
    pinterest_client_id:PINTEREST_CLIENT_ID pinterest_client_secret:PINTEREST_CLIENT_SECRET \
    discord_client_id:DISCORD_CLIENT_ID discord_client_secret:DISCORD_CLIENT_SECRET \
    discord_bot_token_id:DISCORD_BOT_TOKEN_ID \
    mastodon_url:MASTODON_URL mastodon_client_id:MASTODON_CLIENT_ID \
    mastodon_client_secret:MASTODON_CLIENT_SECRET \
    openai_api_key:OPENAI_API_KEY api_limit:API_LIMIT; do
    set_from_opt "${pair%%:*}" "${pair#*:}"
done

EXCLUDE_QUEUE_OPT="$(opt exclude_queues)"
if [ -n "${EXCLUDE_QUEUE_OPT}" ]; then
    if ! printf '%s' "${EXCLUDE_QUEUE_OPT}" | grep -Eq '^[a-z0-9-]+(,[a-z0-9-]+)*$'; then
        die "'exclude_queues' must be a comma-separated list of provider identifiers, e.g. reddit,dribbble"
    fi
    case ",${EXCLUDE_QUEUE_OPT}," in
        *,main,*) die "'exclude_queues' must not contain 'main' (it runs all Postiz workflows)." ;;
    esac
    export EXCLUDE_QUEUE="${EXCLUDE_QUEUE_OPT}"
    log "Temporal worker queues excluded: ${EXCLUDE_QUEUE}"
fi

# Email (optional). With no provider Postiz auto-activates new users.
EMAIL_PROVIDER_OPT="$(opt email_provider none)"
case "${EMAIL_PROVIDER_OPT}" in
    none)
        if [ -n "${EMAIL_PROVIDER:-}" ]; then
            log "Email: provider '${EMAIL_PROVIDER}' set in postiz.env."
        else
            log "Email: not configured (optional; new accounts are activated without e-mail)."
        fi
        ;;
    resend)
        export EMAIL_PROVIDER="resend"
        set_from_opt resend_api_key RESEND_API_KEY
        [ -n "${RESEND_API_KEY:-}" ] || die "email_provider is 'resend' but 'resend_api_key' is empty."
        log "Email: Resend."
        ;;
    nodemailer)
        export EMAIL_PROVIDER="nodemailer"
        set_from_opt smtp_host EMAIL_HOST
        set_from_opt smtp_port EMAIL_PORT
        set_from_opt smtp_user EMAIL_USER
        set_from_opt smtp_password EMAIL_PASS
        EMAIL_SECURE="$(opt_bool smtp_secure true)"
        export EMAIL_SECURE
        [ -n "${EMAIL_HOST:-}" ] || die "email_provider is 'nodemailer' but 'smtp_host' is empty."
        log "Email: SMTP via ${EMAIL_HOST}:${EMAIL_PORT:-default port} (secure=${EMAIL_SECURE})."
        ;;
    *) die "email_provider must be none, resend or nodemailer." ;;
esac
set_from_opt email_from_name EMAIL_FROM_NAME
set_from_opt email_from_address EMAIL_FROM_ADDRESS

# Storage.
case "${STORAGE_PROVIDER_OPT}" in
    local)
        export STORAGE_PROVIDER="local"
        log "Storage: local, files in ${UPLOADS_DIR} (included in Home Assistant backups of this app)."
        ;;
    cloudflare)
        export STORAGE_PROVIDER="cloudflare"
        export CLOUDFLARE_REGION="${CLOUDFLARE_REGION:-auto}"
        for pair in \
            cloudflare_account_id:CLOUDFLARE_ACCOUNT_ID \
            cloudflare_access_key:CLOUDFLARE_ACCESS_KEY \
            cloudflare_secret_access_key:CLOUDFLARE_SECRET_ACCESS_KEY \
            cloudflare_bucket_name:CLOUDFLARE_BUCKETNAME \
            cloudflare_bucket_url:CLOUDFLARE_BUCKET_URL \
            cloudflare_region:CLOUDFLARE_REGION; do
            set_from_opt "${pair%%:*}" "${pair#*:}"
            if [ -z "$(printenv "${pair#*:}" || true)" ]; then
                die "storage_provider is 'cloudflare' but '${pair%%:*}' is empty."
            fi
        done
        log "Storage: Cloudflare R2 bucket '${CLOUDFLARE_BUCKETNAME}'."
        ;;
    *) die "storage_provider must be local or cloudflare." ;;
esac

# --------------------------------------------- managed Postiz variables ------
export MAIN_URL="${EXTERNAL_URL}"
export FRONTEND_URL="${EXTERNAL_URL}"
export NEXT_PUBLIC_BACKEND_URL="${EXTERNAL_URL}/api"
# Backend as seen from inside this container (nginx -> :3000 in upstream).
export BACKEND_INTERNAL_URL="http://localhost:3000"
export JWT_SECRET
DATABASE_URL="postgresql://postiz:$(urlencode "${DB_PASSWORD}")@${PG_HOST}:5432/postiz"
REDIS_URL="redis://:$(urlencode "${REDIS_PASSWORD}")@${REDIS_HOST}:6379"
export DATABASE_URL REDIS_URL
export TEMPORAL_ADDRESS="${TEMPORAL_HOST}:7233"
export TEMPORAL_NAMESPACE="default"
export IS_GENERAL="true"
export RUN_CRON="true"
export UPLOAD_DIRECTORY="/uploads"
export NEXT_PUBLIC_UPLOAD_STATIC_DIRECTORY="/uploads"
if [ "$(opt_bool disable_registration true)" = "true" ]; then
    export DISABLE_REGISTRATION="true"
    log "Registration: closed after the first account (Postiz still lets the very first user sign up at ${EXTERNAL_URL}/auth)."
else
    export DISABLE_REGISTRATION="false"
    warn "Registration: OPEN - anyone who can reach ${EXTERNAL_URL} can create an account."
fi

# ------------------------------------------------------- dependencies ------
pg_login() {
    PGPASSWORD="${DB_PASSWORD}" PGCONNECT_TIMEOUT=5 psql -X -q -h "${PG_HOST}" -p 5432 \
        -U postiz -d postiz -tAc 'SELECT 1' 2>&1
}
redis_ping() {
    REDISCLI_AUTH="${REDIS_PASSWORD}" timeout 5 redis-cli -h "${REDIS_HOST}" -p 6379 ping 2>&1
}
redis_ok() {
    [ "$(redis_ping)" = "PONG" ]
}
# shellcheck disable=SC2329 # invoked indirectly via wait_until
temporal_ok() {
    curl -fsS -o /dev/null --max-time 5 "http://${TEMPORAL_HOST}:7243/api/v1/namespaces/default"
}

# PostgreSQL
wait_until "PostgreSQL host name '${PG_HOST}' to resolve" "${WAIT_TIMEOUT}" host_resolves "${PG_HOST}" \
    || die "'${PG_HOST}' does not resolve. Is 'Postiz PostgreSQL' installed from this repository and started?"
wait_until "PostgreSQL" "${WAIT_TIMEOUT}" pg_isready -q -h "${PG_HOST}" -p 5432 -d postiz -U postiz -t 3 \
    || die "PostgreSQL at ${PG_HOST}:5432 did not become ready within ${WAIT_TIMEOUT}s. Check the 'Postiz PostgreSQL' app log."
login_ok=false
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if out="$(pg_login)"; then
        login_ok=true
        break
    fi
    case "${out}" in
        *"password authentication failed"*)
            die "PostgreSQL rejected the password for user 'postiz'. 'database_password' here must equal 'postiz_password' in the Postiz PostgreSQL app."
            ;;
    esac
    sleep 3
done
[ "${login_ok}" = "true" ] || die "Could not log in to PostgreSQL as 'postiz'. Check the Postiz PostgreSQL app log."
log "PostgreSQL login as 'postiz' verified."

# Redis
wait_until "Redis host name '${REDIS_HOST}' to resolve" "${WAIT_TIMEOUT}" host_resolves "${REDIS_HOST}" \
    || die "'${REDIS_HOST}' does not resolve. Is 'Postiz Redis' installed from this repository and started?"
wait_until "Redis port" "${WAIT_TIMEOUT}" tcp_open "${REDIS_HOST}" 6379 \
    || die "Redis at ${REDIS_HOST}:6379 is not accepting connections. Check the 'Postiz Redis' app log."
if ! redis_ok; then
    case "$(redis_ping)" in
        *WRONGPASS* | *NOAUTH* | *invalid\ password* | *"invalid username-password"*)
            die "Redis rejected the password. 'redis_password' here must equal 'password' in the Postiz Redis app."
            ;;
    esac
    wait_until "Redis PING" 60 redis_ok || die "Redis does not answer PING. Check the 'Postiz Redis' app log."
fi
log "Redis PING/PONG with authentication verified."

# Temporal (namespace "default" must exist before the Postiz backend starts,
# otherwise the backend can hang without binding its port - Postiz #2026).
wait_until "Temporal host name '${TEMPORAL_HOST}' to resolve" "${WAIT_TIMEOUT}" host_resolves "${TEMPORAL_HOST}" \
    || die "'${TEMPORAL_HOST}' does not resolve. Is 'Postiz Temporal' installed from this repository and started?"
wait_until "Temporal (namespace 'default')" "${WAIT_TIMEOUT}" temporal_ok \
    || die "Temporal at ${TEMPORAL_HOST} did not report namespace 'default' within ${WAIT_TIMEOUT}s. Check the 'Postiz Temporal' app log."
tcp_open "${TEMPORAL_HOST}" 7233 || die "Temporal HTTP API answers but gRPC port 7233 is closed."

unset DB_PASSWORD REDIS_PASSWORD
# Postiz never talks to the Supervisor; don't hand it the API token.
unset SUPERVISOR_TOKEN HASSIO_TOKEN

# ------------------------------------------------------------ start ------
cd /app

BACKGROUND_PIDS=()
APP_PID=""

stop_background() {
    local pid
    for pid in "${BACKGROUND_PIDS[@]}"; do
        kill "${pid}" 2> /dev/null || true
    done
}

# shellcheck disable=SC2329 # invoked by trap
on_term() {
    trap - TERM INT
    log "Stop requested: stopping Postiz processes gracefully..."
    pm2 kill > /dev/null 2>&1 || true
    nginx -s quit > /dev/null 2>&1 || true
    if [ -n "${APP_PID}" ]; then
        kill -TERM "${APP_PID}" 2> /dev/null || true
        wait "${APP_PID}" 2> /dev/null || true
    fi
    stop_background
    log "Postiz stopped."
    exit 0
}
trap on_term TERM INT

# Upstream never rotates these files; keep them from filling the disk.
housekeeping() {
    local f size
    while true; do
        sleep 600
        for f in /root/.pm2/logs/*.log /root/.pm2/pm2.log /var/log/nginx/*.log; do
            [ -f "${f}" ] || continue
            size="$(stat -c %s "${f}" 2> /dev/null || echo 0)"
            if [ "${size}" -gt 20971520 ]; then
                : > "${f}"
                log "Truncated ${f} (was $((size / 1048576)) MB)."
            fi
        done
    done
}

readiness() {
    local deadline code
    deadline=$(($(date +%s) + 1200))
    while [ "$(date +%s)" -lt "${deadline}" ]; do
        if curl -fs -o /dev/null --max-time 5 http://127.0.0.1:5000/api/ 2> /dev/null; then
            code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://127.0.0.1:5000/auth || true)"
            case "${code}" in
                2* | 3*)
                    log "Postiz is ready: backend and frontend answer on port 5000. Open ${EXTERNAL_URL}"
                    return 0
                    ;;
            esac
        fi
        sleep 10
    done
    warn "Postiz did not answer on port 5000 within 20 minutes; check the messages above."
}

log "Starting nginx on port 5000 (as upstream)."
nginx

housekeeping &
BACKGROUND_PIDS+=("$!")
readiness &
BACKGROUND_PIDS+=("$!")

log "Starting Postiz: prisma db push (schema sync), then backend, frontend and orchestrator under pm2."
pnpm run pm2 &
APP_PID="$!"

set +e
wait "${APP_PID}"
rc=$?
set -e
trap - TERM INT
warn "Postiz process tree exited with code ${rc}."
pm2 kill > /dev/null 2>&1 || true
nginx -s quit > /dev/null 2>&1 || true
stop_background
if [ "${rc}" -eq 0 ]; then
    rc=1
fi
exit "${rc}"
