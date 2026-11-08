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
readonly MODULE_SCRIPT="$(realpath "${BASH_SOURCE[0]}")"
readonly MODULE_DESCRIPTION="External connectivity monitoring (ping)"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-120}
MODULE_INTERVAL_NORMAL=${MODULE_INTERVAL_NORMAL:-}
MODULE_INTERVAL_ALT=${MODULE_INTERVAL_ALT:-}
MODULE_ORDER=${MODULE_ORDER:-70}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly CONNECTIVITY_TARGET="${CONNECTIVITY_TARGET:-1.1.1.1}"

readonly CONNECTIVITY_PING_COUNT="${CONNECTIVITY_PING_COUNT:-3}"
readonly CONNECTIVITY_PING_TIMEOUT_SECONDS="${CONNECTIVITY_PING_TIMEOUT_SECONDS:-5}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

CONNECTIVITY_STATUS="${SW_STATUS_OK}"
CONNECTIVITY_REACHABLE="false"
CONNECTIVITY_RESULT="error"
CONNECTIVITY_ERROR=""

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

connectivity_collect() {

    local ping_rc
    local text

    CONNECTIVITY_REACHABLE="false"
    CONNECTIVITY_RESULT="error"
    CONNECTIVITY_ERROR=""

    sw_require_command ping || return 127

    #
    # Validate ping count.
    #

    if [[ ! "${CONNECTIVITY_PING_COUNT}" =~ ^[0-9]+$ ]] ||
        [[ ! "${CONNECTIVITY_PING_COUNT}" =~ [1-9] ]]; then

        CONNECTIVITY_ERROR="$(sw_translate "Invalid CONNECTIVITY_PING_COUNT: must be a positive integer")"

        return 0

    fi

    #
    # Validate ping timeout.
    #

    if [[ ! "${CONNECTIVITY_PING_TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]] ||
        [[ ! "${CONNECTIVITY_PING_TIMEOUT_SECONDS}" =~ [1-9] ]]; then

        CONNECTIVITY_ERROR="$(sw_translate "Invalid CONNECTIVITY_PING_TIMEOUT_SECONDS: must be a positive integer")"

        return 0

    fi

    #
    # Execute ping.
    #

    if ping \
        -c "${CONNECTIVITY_PING_COUNT}" \
        -W "${CONNECTIVITY_PING_TIMEOUT_SECONDS}" \
        "${CONNECTIVITY_TARGET}" >/dev/null 2>&1; then

        ping_rc=0

    else

        ping_rc=$?

    fi

    #
    # Interpret ping result.
    #

    case "${ping_rc}" in

    0)

        CONNECTIVITY_RESULT="reachable"
        CONNECTIVITY_REACHABLE="true"

        ;;

    1)

        CONNECTIVITY_RESULT="unreachable"

        ;;

    *)

        CONNECTIVITY_RESULT="error"

        text="$(sw_translate "Ping execution failed (exit code")"

        CONNECTIVITY_ERROR="${text} ${ping_rc})"

        ;;

    esac

    return 0

}

connectivity_analyze() {

    CONNECTIVITY_STATUS="${SW_STATUS_OK}"

    case "${CONNECTIVITY_RESULT}" in

    reachable)

        CONNECTIVITY_STATUS="${SW_STATUS_OK}"

        ;;

    unreachable)

        CONNECTIVITY_STATUS="${SW_STATUS_CRITICAL}"

        ;;

    error)

        CONNECTIVITY_STATUS="${SW_STATUS_UNKNOWN}"

        ;;

    *)

        CONNECTIVITY_STATUS="${SW_STATUS_UNKNOWN}"

        ;;

    esac

}

connectivity_update_state() {

    local text

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.label" "$(sw_translate "Connectivity")"
    sw_state_set "module.icon" "lucide/wifi"
    sw_state_set "module.order" "$MODULE_ORDER"

    local detail

    case "${CONNECTIVITY_RESULT}" in

    reachable)

        #detail="IP externa ${CONNECTIVITY_TARGET} responde"
        detail="$(printf "$(sw_translate "External IP %s responds")\n" \
            "${CONNECTIVITY_TARGET}")"

        ;;

    unreachable)

        #detail="IP externa ${CONNECTIVITY_TARGET} no responde (${CONNECTIVITY_PING_COUNT} intentos)"
        detail="$(printf "$(sw_translate "External IP %s not responding (%s attempts)")\n" \
            "${CONNECTIVITY_TARGET}" "${CONNECTIVITY_PING_COUNT}")"

        ;;

    error)

        #detail="No se pudo realizar la prueba de conectividad: ${CONNECTIVITY_ERROR}"
        detail="$(printf "$(sw_translate "The connectivity test could not be performed: %s")\n" \
            "${CONNECTIVITY_ERROR}")"

        ;;

    *)

        detail="$(sw_translate "Unknown connectivity result")"

        ;;

    esac

    sw_state_set "detail" "${detail}"
    sw_state_set "detail.label" "$(sw_translate "Detail")"

}

connectivity_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Connectivity: ${CONNECTIVITY_TARGET} result=${CONNECTIVITY_RESULT} (${CONNECTIVITY_STATUS})"

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
