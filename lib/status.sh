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

_sw_status_update() {

    local status="$1"
    local event_module="$2"

    _sw_status_validate "${status}" || return 1

    local previous_status
    local status_since
    local now

    now="$(sw_timestamp)"

    previous_status="$(sw_state_get status)"
    status_since="$(sw_state_get status_since)"

    if [[ -z "${previous_status}" ]]; then

        sw_log_info \
            "${event_module}" \
            "Initial status: ${status}"

        sw_event \
            "${status}" \
            "${event_module}" \
            "Initial status: ${status}"

        status_since="${now}"

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

    [[ -n "${status_since}" ]] || status_since="${now}"

    sw_state_set status "${status}"
    sw_state_set status_since "${status_since}"
    sw_state_set timestamp "${now}"

}

# -----------------------------------------------------------------------------
# Public functions
# -----------------------------------------------------------------------------

sw_status_update() {

    local status="$1"
    local detail="${2:-}"
    local event_module="${MODULE_NAME}"

    [[ -n "${detail}" ]] &&
        event_module="${MODULE_NAME}:${detail}"

    _sw_status_update "${status}" "${event_module}"

}

sw_status_update_for() {

    local module="$1"
    local status="$2"

    sw_state_use "${module}"
    sw_state_load

    _sw_status_update "${status}" "${module}"

    sw_state_save

}
