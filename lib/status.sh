#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Status handling
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Status constants
# -----------------------------------------------------------------------------

readonly SW_STATUS_UNKNOWN="UNKNOWN"
readonly SW_STATUS_OK="OK"
readonly SW_STATUS_INFO="INFO"
readonly SW_STATUS_WARNING="WARNING"
readonly SW_STATUS_CRITICAL="CRITICAL"
readonly SW_STATUS_DISABLED="DISABLED"

# -----------------------------------------------------------------------------
# Private functions
# -----------------------------------------------------------------------------

_sw_status_validate() {

    local status="$1"

    case "${status}" in

        "${SW_STATUS_UNKNOWN}" \
        | "${SW_STATUS_OK}" \
        | "${SW_STATUS_INFO}" \
        | "${SW_STATUS_WARNING}" \
        | "${SW_STATUS_CRITICAL}" \
        | "${SW_STATUS_DISABLED}")

            return 0
            ;;

        *)

            sw_log_error \
                "Status" \
                "Invalid status: ${status}"

            return 1
            ;;

    esac

}

# -----------------------------------------------------------------------------
# Public functions
# -----------------------------------------------------------------------------

sw_status_update() {

    local status="$1"
    local detail="${2:-}"

    _sw_status_validate "${status}" || return 1

    local previous_status
    local status_since
    local now
    local event_module

    now="$(sw_timestamp)"

    event_module="${MODULE_NAME}"
    [[ -n "${detail}" ]] && event_module="${MODULE_NAME}:${detail}"

    previous_status="$(sw_state_get status)"
    status_since="$(sw_state_get status_since)"

    # -------------------------------------------------------------------------
    # First execution
    # -------------------------------------------------------------------------

    if [[ -z "${previous_status}" ]]; then

        sw_log_info \
            "${event_module}" \
            "Initial status: ${status}"

        sw_event \
            "${status}" \
            "${event_module}" \
            "Initial status: ${status}"

        status_since="${now}"

    # -------------------------------------------------------------------------
    # Status changed
    # -------------------------------------------------------------------------

    elif [[ "${previous_status}" != "${status}" ]]; then

        sw_log_info \
            "${event_module}" \
            "Status changed: ${previous_status} -> ${status}"

        sw_event \
            "${status}" \
            "${event_module}" \
            "Status changed: ${previous_status} -> ${status}"

        status_since="${now}"

    fi

    # -------------------------------------------------------------------------
    # Keep previous timestamp if status didn't change
    # -------------------------------------------------------------------------

    [[ -n "${status_since}" ]] || status_since="${now}"

    # -------------------------------------------------------------------------
    # Update state
    # -------------------------------------------------------------------------

    sw_state_set status "${status}"
    sw_state_set status_since "${status_since}"
    sw_state_set timestamp "${now}"

}