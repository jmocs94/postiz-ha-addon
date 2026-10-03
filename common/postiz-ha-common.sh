#!/usr/bin/env bash
# shellcheck shell=bash
# -----------------------------------------------------------------------------
# postiz-ha-common.sh - shared helpers for the Postiz Home Assistant app suite.
#
# CANONICAL COPY: common/postiz-ha-common.sh in the repository root.
# Each app's build context is its own folder, so this file is copied into
# <app>/rootfs/usr/local/lib/postiz-ha/common.sh by scripts/sync-common.sh.
# CI (lint workflow) fails if the copies drift. Edit the canonical copy only.
#
# This file is sourced, never executed. It must not print secrets.
# -----------------------------------------------------------------------------

POSTIZ_HA_OPTIONS_FILE="${POSTIZ_HA_OPTIONS_FILE:-/data/options.json}"
POSTIZ_HA_COMPONENT="${POSTIZ_HA_COMPONENT:-postiz-ha}"

# --- logging -----------------------------------------------------------------

log() {
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${POSTIZ_HA_COMPONENT}" "$*"
}

warn() {
    printf '%s [%s] WARNING: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${POSTIZ_HA_COMPONENT}" "$*" >&2
}

die() {
    printf '%s [%s] FATAL: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${POSTIZ_HA_COMPONENT}" "$*" >&2
    exit 1
}

# --- options -----------------------------------------------------------------

# opt KEY [DEFAULT]
# Prints the value of a top-level key from /data/options.json.
# Booleans are printed as "true"/"false". Missing/null keys print DEFAULT.
opt() {
    local key="$1"
    local default="${2:-}"
    local value
    [ -r "${POSTIZ_HA_OPTIONS_FILE}" ] || die "Cannot read ${POSTIZ_HA_OPTIONS_FILE}."
    value="$(jq -r --arg k "${key}" \
        'if has($k) and .[$k] != null then (.[$k] | tostring) else empty end' \
        "${POSTIZ_HA_OPTIONS_FILE}")" || die "Cannot parse ${POSTIZ_HA_OPTIONS_FILE}."
    if [ -z "${value}" ]; then
        printf '%s' "${default}"
    else
        printf '%s' "${value}"
    fi
}

# opt_bool KEY DEFAULT(true|false) -> prints true or false
opt_bool() {
    local value
    value="$(opt "$1" "$2")"
    case "${value}" in
        true | True | TRUE | 1 | yes | on) printf 'true' ;;
        *) printf 'false' ;;
    esac
}

# require_password LABEL VALUE OPTION_NAME
# Passwords are restricted to a URL-, YAML- and shell-safe alphabet so they can
# be embedded in connection strings and in Temporal's generated YAML config
# without escaping bugs. 16-128 characters.
require_password() {
    local label="$1"
    local value="$2"
    local option_name="$3"
    if [ -z "${value}" ]; then
        die "${label} is not set. Open this app's Configuration tab and set '${option_name}'. Generate one with: openssl rand -hex 24"
    fi
    if ! printf '%s' "${value}" | grep -Eq '^[A-Za-z0-9._~-]{16,128}$'; then
        die "${label} ('${option_name}') must be 16-128 characters using only letters, digits and . _ ~ - (generate one with: openssl rand -hex 24)."
    fi
}

# urlencode VALUE
urlencode() {
    jq -rn --arg v "$1" '$v|@uri'
}

# --- sibling discovery -------------------------------------------------------
#
# Supervisor gives every app container the hostname "{REPO}-{SLUG}" where
# {REPO} is "local" or an 8-char hash of the repository URL and underscores are
# replaced with hyphens (supervisor/apps/model.py: hostname = slug.replace("_","-")).
# All apps installed from this repository share the same {REPO} prefix, so an
# app can derive its siblings' hostnames from its own hostname.

self_hostname() {
    local h=""
    if [ -r /etc/hostname ]; then
        h="$(tr -d '[:space:]' < /etc/hostname)"
    fi
    if [ -z "${h}" ]; then
        h="$(hostname 2>/dev/null || true)"
    fi
    printf '%s' "${h}"
}

# repo_prefix OWN_SLUG -> prints "local" or the repository hash
repo_prefix() {
    local own_dns="${1//_/-}"
    local host prefix repo
    host="$(self_hostname)"
    case "${host}" in
        *-"${own_dns}")
            prefix="${host%-"${own_dns}"}"
            if [ -n "${prefix}" ]; then
                printf '%s' "${prefix}"
                return 0
            fi
            ;;
    esac
    # Fallback: ask the Supervisor about ourselves. /addons/self/info is
    # available to every app without hassio_api (api_bypass in Supervisor).
    if [ -n "${SUPERVISOR_TOKEN:-}" ] && command -v curl > /dev/null 2>&1; then
        repo="$(curl -fsS --max-time 10 \
            -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
            http://supervisor/addons/self/info 2> /dev/null \
            | jq -r '.data.repository // empty' 2> /dev/null || true)"
        if [ -n "${repo}" ]; then
            printf '%s' "${repo//_/-}"
            return 0
        fi
    fi
    return 1
}

# sibling_host OWN_SLUG TARGET_SLUG [OVERRIDE]
sibling_host() {
    local own_slug="$1"
    local target_slug="$2"
    local override="${3:-}"
    local prefix
    if [ -n "${override}" ]; then
        require_hostname "Host override for ${target_slug}" "${override}"
        printf '%s' "${override}"
        return 0
    fi
    prefix="$(repo_prefix "${own_slug}")" \
        || die "Could not determine this repository's app prefix from hostname '$(self_hostname)'. Set the host override option for ${target_slug} manually."
    printf '%s-%s' "${prefix}" "${target_slug//_/-}"
}

# host_resolves HOST
# Without getent (minimal images) resolution is left to the TCP check.
host_resolves() {
    if command -v getent > /dev/null 2>&1; then
        getent hosts "$1" > /dev/null 2>&1
    else
        return 0
    fi
}

# --- waiting -----------------------------------------------------------------

# wait_until DESCRIPTION TIMEOUT_SECONDS COMMAND [ARGS...]
# Runs COMMAND every 3 seconds until it succeeds or TIMEOUT_SECONDS pass.
# Logs a progress line every 30 seconds instead of every attempt.
wait_until() {
    local description="$1"
    local timeout="$2"
    shift 2
    local start now elapsed last_report=0
    start="$(date +%s)"
    log "Waiting for ${description}..."
    while true; do
        if "$@" > /dev/null 2>&1; then
            now="$(date +%s)"
            log "${description} ready (after $((now - start))s)."
            return 0
        fi
        now="$(date +%s)"
        elapsed=$((now - start))
        if [ "${elapsed}" -ge "${timeout}" ]; then
            return 1
        fi
        if [ $((elapsed - last_report)) -ge 30 ]; then
            log "Still waiting for ${description} (${elapsed}s of ${timeout}s)..."
            last_report="${elapsed}"
        fi
        sleep 3
    done
}

# tcp_open HOST PORT (bash /dev/tcp, no external tools needed)
tcp_open() {
    # shellcheck disable=SC2016 # $1/$2 are expanded by the inner bash
    timeout 3 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$1" "$2" > /dev/null 2>&1
}

# require_hostname LABEL VALUE - rejects anything that is not a plain host name
require_hostname() {
    if ! printf '%s' "$2" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$'; then
        die "$1 '$2' is not a valid host name."
    fi
}
