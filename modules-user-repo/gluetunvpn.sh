#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Gluetun VPN status monitoring module
#
# Purely observational: reads Gluetun's own control server API. Does not
# rotate servers, restart containers, or fix anything -- that decision is
# yours to make (see healthcheck.sh in this project for an example of a
# script that does take action, tailored to one specific setup).
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="GluetunVPN"
readonly MODULE_DESCRIPTION="Gluetun VPN status monitoring"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-120}
MODULE_ORDER=${MODULE_ORDER:-70}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# Gluetun's control server default port is 8000; adjust to whatever you
# mapped it to.
readonly GLUETUN_API_URL="${GLUETUN_API_URL:-http://localhost:8000}"

# Optional: only needed if you configured apikey authentication on
# Gluetun's control server (required by default since Gluetun 3.40+).
# Leave empty if you set auth to "none" or use basic auth instead (not
# supported by this module yet).
readonly GLUETUN_API_KEY="${GLUETUN_API_KEY:-}"

readonly GLUETUN_TIMEOUT_SECONDS="${GLUETUN_TIMEOUT_SECONDS:-10}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

GLUETUN_VPN_STATUS=""
GLUETUN_VPN_TYPE=""
GLUETUN_PROVIDER=""
GLUETUN_INTERFACE=""
GLUETUN_PUBLIC_IP=""
GLUETUN_REGION=""
GLUETUN_COUNTRY=""
GLUETUN_CITY=""
GLUETUN_PORT_FORWARD=""
GLUETUN_STATUS="${SW_STATUS_OK}"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

gluetun_curl() {

    # Small wrapper so every call gets the same timeout and optional
    # header without repeating it four times.

    local path="$1"

    local curl_args=(
        --silent
        --show-error
        --max-time "${GLUETUN_TIMEOUT_SECONDS}"
    )

    [[ -n "${GLUETUN_API_KEY}" ]] &&
        curl_args+=(-H "X-API-Key: ${GLUETUN_API_KEY}")

    curl "${curl_args[@]}" "${GLUETUN_API_URL}${path}" 2>/dev/null

}

gluetun_collect() {

    sw_require_command curl || return 127
    sw_require_command jq || return 127

    local status_json
    status_json="$(gluetun_curl "/v1/vpn/status")"

    if [[ -z "${status_json}" ]]; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "No response from Gluetun control server at ${GLUETUN_API_URL} (unreachable, or auth failed)"

        return 1

    fi

    GLUETUN_VPN_STATUS="$(jq -r '.status // "unknown"' <<< "${status_json}")"

    local settings_json
    settings_json="$(gluetun_curl "/v1/vpn/settings")"

    GLUETUN_VPN_TYPE="$(jq -r '.type // "unknown"' <<< "${settings_json}")"
    GLUETUN_PROVIDER="$(jq -r '.provider.name // "unknown"' <<< "${settings_json}")"
    GLUETUN_INTERFACE="$(
        jq -r '.openvpn.interface // .wireguard.interface // "unknown"' <<< "${settings_json}"
    )"

    local ip_json
    ip_json="$(gluetun_curl "/v1/publicip/ip")"

    GLUETUN_PUBLIC_IP="$(jq -r '.public_ip // "unknown"' <<< "${ip_json}")"
    GLUETUN_REGION="$(jq -r '.region // ""' <<< "${ip_json}")"
    GLUETUN_COUNTRY="$(jq -r '.country // ""' <<< "${ip_json}")"
    GLUETUN_CITY="$(jq -r '.city // ""' <<< "${ip_json}")"

    local pf_json
    pf_json="$(gluetun_curl "/v1/portforward")"

    GLUETUN_PORT_FORWARD="$(jq -r '.port // "N/A"' <<< "${pf_json}")"

}

gluetun_analyze() {

    GLUETUN_STATUS="${SW_STATUS_OK}"

    if [[ "${GLUETUN_VPN_STATUS}" != "running" ]]; then

        GLUETUN_STATUS="${SW_STATUS_CRITICAL}"

    fi

}

gluetun_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.label" "Gluetun VPN"
    sw_state_set "module.icon" "lucide/router"
    sw_state_set "module.order" "$MODULE_ORDER"

    sw_state_set "vpn_status" "$(sw_translate "${GLUETUN_VPN_STATUS}")"
    sw_state_set "vpn_status.label" "$(sw_translate "VPN status")"
    sw_state_set "vpn_status.order" "10"

    sw_state_set "vpn_type" "${GLUETUN_VPN_TYPE}"
    sw_state_set "vpn_type.label" "$(sw_translate "Type")"
    sw_state_set "vpn_type.order" "20"

    sw_state_set "provider" "${GLUETUN_PROVIDER}"
    sw_state_set "provider.label" "$(sw_translate "Provider")"
    sw_state_set "provider.order" "25"

    sw_state_set "interface" "${GLUETUN_INTERFACE}"
    sw_state_set "interface.label" "$(sw_translate "Interface")"
    sw_state_set "interface.order" "30"

    sw_state_set "public_ip" "${GLUETUN_PUBLIC_IP}"
    sw_state_set "public_ip.label" "$(sw_translate "Public IP")"
    sw_state_set "public_ip.order" "40"

    local location="${GLUETUN_CITY}"
    [[ -n "${GLUETUN_REGION}" ]] && location="${location}, ${GLUETUN_REGION}"
    [[ -n "${GLUETUN_COUNTRY}" ]] && location="${location} (${GLUETUN_COUNTRY})"

    sw_state_set "location" "${location}"
    sw_state_set "location.label" "$(sw_translate "Location")"
    sw_state_set "location.order" "50"

    sw_state_set "port_forward" "${GLUETUN_PORT_FORWARD}"
    sw_state_set "port_forward.label" "$(sw_translate "Port Forward")"
    sw_state_set "port_forward.order" "60"

}

gluetun_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Gluetun: status=${GLUETUN_VPN_STATUS} provider=${GLUETUN_PROVIDER} ip=${GLUETUN_PUBLIC_IP} (${GLUETUN_STATUS})"

}

sw_module_run() {

    sw_state_use "gluetun_vpn1"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi
    
    sw_state_load

    gluetun_collect || return 1

    gluetun_analyze

    sw_status_update "${GLUETUN_STATUS}" || return 1

    gluetun_update_state

    sw_state_save

    gluetun_report

    sw_csv_append \
        "gluetun" \
        "interface" \
        "${GLUETUN_INTERFACE}"

    sw_csv_append \
        "gluetun" \
        "public_ip" \
        "${GLUETUN_PUBLIC_IP}"    

    sw_csv_append \
        "gluetun" \
        "port" \
        "${GLUETUN_PORT_FORWARD}"    

}
