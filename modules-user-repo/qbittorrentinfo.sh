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
MODULE_INTERVAL=${MODULE_INTERVAL:-120}
MODULE_INTERVAL_NORMAL=${MODULE_INTERVAL_NORMAL:-}
MODULE_INTERVAL_ALT=${MODULE_INTERVAL_ALT:-}
MODULE_ORDER=${MODULE_ORDER:-70}
MODULE_REMOTE=${MODULE_REMOTE:-""}

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
QBITTORRENT_DHT_NODES=0
QBITTORRENT_DOWN_LIMIT=0
QBITTORRENT_UP_LIMIT=0

QBITTORRENT_PORT=0
QBITTORRENT_INTERFACE=""
QBITTORRENT_INTERFACE_ADDRESS=""
QBITTORRENT_EXTERNAL_ADDRESS=""
QBITTORRENT_INTERFACE_NAME=""
QBITTORRENT_UPNP=false
QBITTORRENT_RANDOM_PORT=false

QBITTORRENT_STATUS="${SW_STATUS_OK}"

QBITTORRENT_ID=""
QBITTORRENT_NAMESPACE=""
QBITTORRENT_NETWORK_ID=""

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

    echo "$http_code" | jq . >~/scripts/syswatch/cache/qbittorrent_login.json

    case "${http_code}" in
    200 | 204)
        return 0
        ;;
    *)
        return 1
        ;;
    esac

}

qbittorrent_collect() {

    sw_require_command curl || return 127
    sw_require_command jq || return 127

    # -------------------------------------------------------------------------
    # Get container ID and network namespace
    # -------------------------------------------------------------------------

    QBITTORRENT_ID=""
    QBITTORRENT_NAMESPACE=""

    case "${QBITTORRENT_MODE}" in

    host)
        # No Docker checks required.
        ;;

    docker)

        sw_require_command docker || return 127

        QBITTORRENT_ID="$(
            docker inspect \
                --format '{{.Id}}' \
                "${QBITTORRENT_CONTAINER_NAME}" 2>/dev/null
        )" || {
            sw_log_warning \
                "${MODULE_NAME}" \
                "Unable to get qBittorrent container ID"

            return 1
        }

        if [[ -z "${QBITTORRENT_ID}" ]]; then

            sw_log_warning \
                "${MODULE_NAME}" \
                "qBittorrent container ID is empty"

            return 1

        fi

        local network_mode

        network_mode="$(
            docker inspect \
                --format '{{.HostConfig.NetworkMode}}' \
                "${QBITTORRENT_CONTAINER_NAME}" 2>/dev/null
        )" || return 1

        QBITTORRENT_NETWORK_ID=""

        if [[ "${network_mode}" == container:* ]]; then
            QBITTORRENT_NETWORK_ID="${network_mode#container:}"
        fi

        QBITTORRENT_NAMESPACE="$(
            docker exec "${QBITTORRENT_CONTAINER_NAME}" \
                readlink /proc/1/ns/net 2>/dev/null
        )" || {
            QBITTORRENT_ID=""
            QBITTORRENT_NAMESPACE=""

            sw_log_warning \
                "${MODULE_NAME}" \
                "Unable to get qBittorrent network namespace"

            return 1
        }

        if [[ -z "${QBITTORRENT_NAMESPACE}" ]]; then

            QBITTORRENT_ID=""

            sw_log_warning \
                "${MODULE_NAME}" \
                "qBittorrent network namespace is empty"

            return 1

        fi

        ;;

    *)

        sw_log_warning \
            "${MODULE_NAME}" \
            "Invalid QBITTORRENT_MODE: ${QBITTORRENT_MODE}"

        return 1
        ;;

    esac

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

    echo "$response" | jq . >~/scripts/syswatch/cache/qbittorrent.json

    if [[ -z "${response}" ]]; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "No response from qBittorrent WebUI at ${QBITTORRENT_URL}"

        rm -f "${cookie_jar}"
        return 1

    fi

    QBITTORRENT_CONNECTION_STATUS="$(jq -r '.connection_status // "unknown"' <<<"${response}")"
    QBITTORRENT_DOWN="$(jq -r '.dl_info_speed // 0' <<<"${response}")"
    QBITTORRENT_UP="$(jq -r '.up_info_speed // 0' <<<"${response}")"
    QBITTORRENT_DHT_NODES="$(jq -r '.dht_nodes // 0' <<<"${response}")"
    QBITTORRENT_DOWN_LIMIT="$(jq -r '.dl_rate_limit // 0' <<<"${response}")"
    QBITTORRENT_UP_LIMIT="$(jq -r '.up_rate_limit // 0' <<<"${response}")"
    QBITTORRENT_EXTERNAL_ADDRESS="$(jq -r '.last_external_address_v4 // 0' <<<"${response}")"

    local preferences
    preferences="$(
        curl \
            --silent \
            --show-error \
            --max-time "${QBITTORRENT_TIMEOUT_SECONDS}" \
            -b "${cookie_jar}" \
            "${QBITTORRENT_URL}/api/v2/app/preferences" \
            2>/dev/null
    )"

    if [[ -z "${preferences}" ]]; then

        rm -f "${cookie_jar}"

        sw_log_warning \
            "${MODULE_NAME}" \
            "No response from qBittorrent preferences API"

        return 1

    fi

    QBITTORRENT_PORT="$(jq -r '.listen_port // 0' <<<"${preferences}")"
    QBITTORRENT_INTERFACE="$(jq -r '.current_interface_name // ""' <<<"${preferences}")"
    QBITTORRENT_INTERFACE_ADDRESS="$(jq -r '.current_interface_address // ""' <<<"${preferences}")"
    QBITTORRENT_UPNP="$(jq -r '.upnp // false' <<<"${preferences}")"
    QBITTORRENT_RANDOM_PORT="$(jq -r '.random_port // false' <<<"${preferences}")"

    rm -f "${cookie_jar}"

}

qbittorrent_analyze() {

    case "${QBITTORRENT_CONNECTION_STATUS}" in

    connected)

        QBITTORRENT_STATUS="${SW_STATUS_OK}"
        ;;

    firewalled | disconnected)

        QBITTORRENT_STATUS="${SW_STATUS_CRITICAL}"
        ;;

    *)

        QBITTORRENT_STATUS="${SW_STATUS_WARNING}"
        ;;

    esac

}

qbittorrent_update_state() {

    local port
    local interface
    local address
    local id
    local namespace

    sw_message_load "ip"
    address="$MESSAGE_FROM_MODULE"
    sw_message_load "port"
    port="$MESSAGE_FROM_MODULE"
    sw_message_load "interface"
    interface="$MESSAGE_FROM_MODULE"
    sw_message_load "id"
    id="$MESSAGE_FROM_MODULE"
    sw_message_load "namespace"
    namespace="$MESSAGE_FROM_MODULE"

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.label" "qBittorrent"
    sw_state_set "module.icon" "lucide/download"
    sw_state_set "module.order" "$MODULE_ORDER"

    sw_state_set "connection_status" "$(sw_translate "${QBITTORRENT_CONNECTION_STATUS}")"
    sw_state_set "connection_status.label" "$(sw_translate "Status")"
    sw_state_set "connection_status.order" "10"

    sw_state_set "interface" "${QBITTORRENT_INTERFACE}"
    sw_state_set "interface.label" "$(sw_translate "Interface")"
    sw_state_set "interface.order" "20"

    if [[ -n "$interface" ]]; then
        if [[ "$QBITTORRENT_INTERFACE" == "$interface" ]]; then
            sw_state_set "interface.color" "green"
        else
            sw_state_set "interface.color" "red"
        fi
    else
        sw_state_set "interface.color" "white"
    fi

    sw_state_set "interface_address" "${QBITTORRENT_EXTERNAL_ADDRESS}"
    sw_state_set "interface_address.label" "$(sw_translate "Address")"
    sw_state_set "interface_address.order" "40"

    if [[ -n "$address" ]]; then
        if [[ "$QBITTORRENT_EXTERNAL_ADDRESS" == "$address" ]]; then
            sw_state_set "interface_address.color" "green"
        else
            sw_state_set "interface_address.color" "red"
        fi
    else
        sw_state_set "interface_address.color" "white"
    fi

    sw_state_set "port" "${QBITTORRENT_PORT}"
    sw_state_set "port.label" "$(sw_translate "Port")"
    sw_state_set "port.order" "50"

    if [[ -n "$port" ]]; then
        if [[ "$QBITTORRENT_PORT" == "$port" ]]; then
            sw_state_set "port.color" "green"
        else
            sw_state_set "port.color" "red"
        fi
    else
        sw_state_set "port.color" "white"
    fi

    # -------------------------------------------------------------------------
    # Network namespace
    # -------------------------------------------------------------------------

    sw_state_set "network_namespace.label" "$(sw_translate "Gluetun network")"
    sw_state_set "network_namespace.order" "55"

    if [[ "${QBITTORRENT_MODE}" == "host" ]]; then

        sw_state_set "network_namespace" "$(sw_translate "Not checked")"
        sw_state_set "network_namespace.color" "white"
        sw_state_set "network_namespace.hidden" "true"

    elif [[ -z "$id" || -z "$namespace" ]]; then

        sw_state_set "network_namespace" "$(sw_translate "Unknown")"
        sw_state_set "network_namespace.color" "white"

    elif [[ "$QBITTORRENT_NETWORK_ID" == "$id" &&
        "$QBITTORRENT_NAMESPACE" == "$namespace" ]]; then

        sw_state_set "network_namespace" "$(sw_translate "Shared")"
        sw_state_set "network_namespace.color" "green"

    else

        sw_state_set "network_namespace" "$(sw_translate "Mismatch")"
        sw_state_set "network_namespace.color" "red"
        QBITTORRENT_STATUS="$SW_STATUS_CRITICAL"

    fi

    sw_state_set "upnp" "$(sw_translate "${QBITTORRENT_UPNP}")"
    sw_state_set "upnp.label" "UPnP / NAT-PMP"
    sw_state_set "upnp.order" "60"

    sw_state_set "random_port" "$(sw_translate "${QBITTORRENT_RANDOM_PORT}")"
    sw_state_set "random_port.label" "$(sw_translate "Random port")"
    sw_state_set "random_port.order" "70"

    sw_state_set "dht_nodes" "${QBITTORRENT_DHT_NODES}"
    sw_state_set "dht_nodes.label" "$(sw_translate "DHT nodes")"
    sw_state_set "dht_nodes.order" "80"

    sw_state_set "down" "${QBITTORRENT_DOWN}"
    sw_state_set "down.label" "$(sw_translate "Download")"
    sw_state_set "down.unit" "B/s"
    sw_state_set "down.order" "90"

    sw_state_set "up" "${QBITTORRENT_UP}"
    sw_state_set "up.label" "$(sw_translate "Upload")"
    sw_state_set "up.unit" "B/s"
    sw_state_set "up.order" "100"

    sw_state_set "down_limit" "${QBITTORRENT_DOWN_LIMIT}"
    sw_state_set "down_limit.label" "$(sw_translate "Download limits")"
    sw_state_set "down_limit.unit" "B/s"
    sw_state_set "down_limit.order" "110"

    sw_state_set "up_limit" "${QBITTORRENT_UP_LIMIT}"
    sw_state_set "up_limit.label" "$(sw_translate "Upload limits")"
    sw_state_set "up_limit.unit" "B/s"
    sw_state_set "up_limit.order" "120"

}

qbittorrent_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "qBittorrent: connection_status=${QBITTORRENT_CONNECTION_STATUS} down=${QBITTORRENT_DOWN} up=${QBITTORRENT_UP} (${QBITTORRENT_STATUS})"

}

sw_module_run() {

    sw_state_use "qbittorrent_info1"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    qbittorrent_collect || return 1

    qbittorrent_analyze

    qbittorrent_update_state

    sw_status_update "${QBITTORRENT_STATUS}" || return 1

    sw_state_save

    qbittorrent_report

}
