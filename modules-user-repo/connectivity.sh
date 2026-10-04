#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Connectivity monitoring module
#
# Purely observational: checks whether an external host responds to ping.
# Does not attempt any fix -- that's a decision for whatever else you have
# running, not this module's job.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Connectivity"
readonly MODULE_DESCRIPTION="External connectivity monitoring (ping)"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-120}
MODULE_ORDER=${MODULE_ORDER:-70}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly CONNECTIVITY_TARGET="${CONNECTIVITY_TARGET:-1.1.1.1}"

# ping succeeds as long as at least ONE of these packets gets a reply, so
# this already tolerates some packet loss without extra debounce logic.
readonly CONNECTIVITY_PING_COUNT="${CONNECTIVITY_PING_COUNT:-3}"
readonly CONNECTIVITY_PING_TIMEOUT_SECONDS="${CONNECTIVITY_PING_TIMEOUT_SECONDS:-5}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

CONNECTIVITY_STATUS="${SW_STATUS_OK}"
CONNECTIVITY_REACHABLE="false"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

connectivity_collect() {

    sw_require_command ping || return 127

    if ping -c "${CONNECTIVITY_PING_COUNT}" -W "${CONNECTIVITY_PING_TIMEOUT_SECONDS}" \
        "${CONNECTIVITY_TARGET}" >/dev/null 2>&1
    then

        CONNECTIVITY_REACHABLE="true"

    else

        CONNECTIVITY_REACHABLE="false"

    fi

}

connectivity_analyze() {

    CONNECTIVITY_STATUS="${SW_STATUS_OK}"

    if [[ "${CONNECTIVITY_REACHABLE}" != "true" ]]; then

        CONNECTIVITY_STATUS="${SW_STATUS_CRITICAL}"

    fi

}

connectivity_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.label" "Conectividad"
    sw_state_set "module.icon" "lucide/wifi"
    sw_state_set "module.order" "$MODULE_ORDER"

    local detail="IP externa ${CONNECTIVITY_TARGET} responde"

    if [[ "${CONNECTIVITY_REACHABLE}" != "true" ]]; then

        detail="IP externa ${CONNECTIVITY_TARGET} no responde (${CONNECTIVITY_PING_COUNT} intentos)"

    fi

    sw_state_set "detail" "${detail}"
    sw_state_set "detail.label" "Detalle"

}

connectivity_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Connectivity: ${CONNECTIVITY_TARGET} reachable=${CONNECTIVITY_REACHABLE} (${CONNECTIVITY_STATUS})"

}

sw_module_run() {

    sw_state_use "connectivity1"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi
    
    sw_state_load

    connectivity_collect || return 1

    connectivity_analyze

    sw_status_update "${CONNECTIVITY_STATUS}" || return 1

    connectivity_update_state

    sw_state_save

    connectivity_report

}
