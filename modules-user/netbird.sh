#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# NetBird VPN monitoring module
#
# Scope, on purpose: only the daemon/management/signal connectivity flips
# the status (that's THIS host's own tunnel being broken). Peer and relay
# counts are shown as informational data only -- a peer showing 0/1
# connected usually just means another device (phone, laptop) is asleep,
# not that anything is actually wrong here.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Netbird"
readonly MODULE_DESCRIPTION="NetBird VPN connectivity monitoring"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-420}
MODULE_ORDER=${MODULE_ORDER:-45}
MODULE_REMOTE=${MODULE_REMOTE:-""}


# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

NETBIRD_DAEMON_STATUS=""
NETBIRD_MANAGEMENT_CONNECTED=""
NETBIRD_SIGNAL_CONNECTED=""
NETBIRD_PEERS_TOTAL=0
NETBIRD_PEERS_CONNECTED=0
NETBIRD_RELAYS_TOTAL=0
NETBIRD_RELAYS_AVAILABLE=0
NETBIRD_STATUS="${SW_STATUS_OK}"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

netbird_collect() {

    sw_require_command netbird || return 127
    sw_require_command jq || return 127

    local json

    json="$(netbird status --json 2>/dev/null)"

    if [[ -z "${json}" ]]; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "'netbird status --json' returned nothing (daemon not running?)"

        return 1

    fi

    NETBIRD_DAEMON_STATUS="$(jq -r '.daemonStatus // "unknown"' <<< "${json}")"
    NETBIRD_MANAGEMENT_CONNECTED="$(jq -r '.management.connected // false' <<< "${json}")"
    NETBIRD_SIGNAL_CONNECTED="$(jq -r '.signal.connected // false' <<< "${json}")"

    NETBIRD_PEERS_TOTAL="$(jq -r '.peers.total // 0' <<< "${json}")"
    NETBIRD_PEERS_CONNECTED="$(jq -r '.peers.connected // 0' <<< "${json}")"

    NETBIRD_RELAYS_TOTAL="$(jq -r '.relays.total // 0' <<< "${json}")"
    NETBIRD_RELAYS_AVAILABLE="$(jq -r '.relays.available // 0' <<< "${json}")"

}

netbird_analyze() {

    NETBIRD_STATUS="${SW_STATUS_OK}"

    if [[ "${NETBIRD_DAEMON_STATUS}" != "Connected" ]]; then

        NETBIRD_STATUS="${SW_STATUS_CRITICAL}"

    elif [[ "${NETBIRD_MANAGEMENT_CONNECTED}" != "true" ]]; then

        NETBIRD_STATUS="${SW_STATUS_CRITICAL}"

    elif [[ "${NETBIRD_SIGNAL_CONNECTED}" != "true" ]]; then

        NETBIRD_STATUS="${SW_STATUS_CRITICAL}"

    fi

}

netbird_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.label" "NetBird"
    sw_state_set "module.icon" "lucide/bird"
    sw_state_set "module.order" "$MODULE_ORDER"

    sw_state_set "daemon" "$(sw_translate "${NETBIRD_DAEMON_STATUS}")"
    sw_state_set "daemon.label" "$(sw_translate "Daemon")"

    sw_state_set "management" "$(sw_translate "${NETBIRD_MANAGEMENT_CONNECTED}")"
    sw_state_set "management.label" "$(sw_translate "Management")"

    sw_state_set "signal" "${NETBIRD_SIGNAL_CONNECTED}"
    sw_state_set "signal.label" "$(sw_translate "Signal")"

    sw_state_set "peers" "${NETBIRD_PEERS_CONNECTED}/${NETBIRD_PEERS_TOTAL}"
    sw_state_set "peers.label" "$(sw_translate "Peers")"

    sw_state_set "relays" "${NETBIRD_RELAYS_AVAILABLE}/${NETBIRD_RELAYS_TOTAL}"
    sw_state_set "relays.label" "$(sw_translate "Relays")"

}

netbird_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "NetBird: daemon=${NETBIRD_DAEMON_STATUS} management=${NETBIRD_MANAGEMENT_CONNECTED} signal=${NETBIRD_SIGNAL_CONNECTED} peers=${NETBIRD_PEERS_CONNECTED}/${NETBIRD_PEERS_TOTAL} (${NETBIRD_STATUS})"

}

sw_module_run() {

    sw_state_use "netbird"
    sw_state_load

    netbird_collect || return 1

    netbird_analyze

    sw_status_update "${NETBIRD_STATUS}" || return 1

    netbird_update_state

    sw_state_save

    netbird_report

}
