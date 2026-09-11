#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# qBittorrent connection status monitoring module
#
# Purely observational: reports connection status and current transfer
# speed. Does not re-apply port forwarding or restart anything -- see
# healthcheck.sh in this project for a script that does take action,
# tailored to one specific setup.
#
# If QBITTORRENT_USER/QBITTORRENT_PASSWORD are set, this logs into the
# WebUI first (most third-party installs have login enabled). If left
# empty, it assumes the WebUI allows unauthenticated access from this
# host (e.g. a "bypass authentication for clients on localhost" rule).
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="QbittorrentInfo"
readonly MODULE_DESCRIPTION="qBittorrent connection status monitoring"
readonly MODULE_VERSION="0.1.0"
readonly MODULE_INTERVAL=120

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly QBITTORRENT_URL="${QBITTORRENT_URL:-http://localhost:8080}"

# Optional: only needed if the WebUI requires login from this host.
readonly QBITTORRENT_USER="${QBITTORRENT_USER:-}"
readonly QBITTORRENT_PASSWORD="${QBITTORRENT_PASSWORD:-}"

readonly QBITTORRENT_TIMEOUT_SECONDS="${QBITTORRENT_TIMEOUT_SECONDS:-10}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

QBITTORRENT_CONNECTION_STATUS=""
QBITTORRENT_DOWN=0
QBITTORRENT_UP=0
QBITTORRENT_STATUS="${SW_STATUS_OK}"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

qbittorrent_login() {

    local cookie_jar="$1"

    local http_code
    http_code="$(
        curl \
            --silent \
            --show-error \
            --max-time "${QBITTORRENT_TIMEOUT_SECONDS}" \
            -c "${cookie_jar}" \
            -o /dev/null \
            -w "%{http_code}" \
            --data-urlencode "username=${QBITTORRENT_USER}" \
            --data-urlencode "password=${QBITTORRENT_PASSWORD}" \
            "${QBITTORRENT_URL}/api/v2/auth/login" \
            2>/dev/null
    )"

    [[ "${http_code}" == "200" ]]

}

qbittorrent_collect() {

    sw_require_command curl || return 127
    sw_require_command jq || return 127

    local cookie_jar
    cookie_jar="$(mktemp)"

    if [[ -n "${QBITTORRENT_USER}" ]]; then

        if ! qbittorrent_login "${cookie_jar}"; then

            sw_log_warning \
                "${MODULE_NAME}" \
                "Login to qBittorrent WebUI failed (check QBITTORRENT_USER/QBITTORRENT_PASSWORD)"

            rm -f "${cookie_jar}"
            return 1

        fi

    fi

    local response
    response="$(
        curl \
            --silent \
            --show-error \
            --max-time "${QBITTORRENT_TIMEOUT_SECONDS}" \
            -b "${cookie_jar}" \
            "${QBITTORRENT_URL}/api/v2/transfer/info" \
            2>/dev/null
    )"

    rm -f "${cookie_jar}"

    if [[ -z "${response}" ]]; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "No response from qBittorrent WebUI at ${QBITTORRENT_URL}"

        return 1

    fi

    QBITTORRENT_CONNECTION_STATUS="$(jq -r '.connection_status // "unknown"' <<< "${response}")"
    QBITTORRENT_DOWN="$(jq -r '.dl_info_speed // 0' <<< "${response}")"
    QBITTORRENT_UP="$(jq -r '.up_info_speed // 0' <<< "${response}")"

}

qbittorrent_analyze() {

    case "${QBITTORRENT_CONNECTION_STATUS}" in

        connected)

            QBITTORRENT_STATUS="${SW_STATUS_OK}"
            ;;

        firewalled|disconnected)

            QBITTORRENT_STATUS="${SW_STATUS_CRITICAL}"
            ;;

        *)

            QBITTORRENT_STATUS="${SW_STATUS_WARNING}"
            ;;

    esac

}

qbittorrent_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.label" "qBittorrent"
    sw_state_set "module.icon" "lucide/download"
    sw_state_set "module.order" "66"

    sw_state_set "connection_status" "${QBITTORRENT_CONNECTION_STATUS}"
    sw_state_set "connection_status.label" "Estado"
    sw_state_set "connection_status.order" "10"

    sw_state_set "down" "${QBITTORRENT_DOWN}"
    sw_state_set "down.label" "Bajada"
    sw_state_set "down.unit" "B/s"
    sw_state_set "down.order" "20"

    sw_state_set "up" "${QBITTORRENT_UP}"
    sw_state_set "up.label" "Subida"
    sw_state_set "up.unit" "B/s"
    sw_state_set "up.order" "30"

}

qbittorrent_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "qBittorrent: connection_status=${QBITTORRENT_CONNECTION_STATUS} down=${QBITTORRENT_DOWN} up=${QBITTORRENT_UP} (${QBITTORRENT_STATUS})"

}

sw_module_run() {

    sw_state_use "qbittorrent_info"
    sw_state_load

    qbittorrent_collect || return 1

    qbittorrent_analyze

    sw_status_update "${QBITTORRENT_STATUS}" || return 1

    qbittorrent_update_state

    sw_state_save

    qbittorrent_report

}
