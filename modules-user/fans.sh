#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# fans module
#
# Reports hardware fan speeds and alarm states.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Fans"
readonly MODULE_DESCRIPTION="Hardware fan speeds"
readonly MODULE_VERSION="0.1.0"

MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-1160}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

FANS_STATUS="${SW_STATUS_UNKNOWN}"

FANS_AVAILABLE=false

declare -a FANS_DATA=()

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

fans_collect() {

    FANS_STATUS="${SW_STATUS_UNKNOWN}"

    FANS_AVAILABLE=false

    FANS_DATA=()

    command -v sensors >/dev/null 2>&1 || return 0

    local output

    output="$(sensors 2>/dev/null)" || return 0

    [[ -n "$output" ]] || return 0

    FANS_AVAILABLE=true

    local line
    local fan_name
    local fan_value
    local fan_alarm

    while IFS= read -r line; do

        # ---------------------------------------------------------------------
        # Fan RPM
        # ---------------------------------------------------------------------

        if [[ "$line" =~ ^(fan[0-9]+):[[:space:]]*([0-9]+)[[:space:]]*RPM(.*)$ ]]; then

            fan_name="${BASH_REMATCH[1]}"
            fan_value="${BASH_REMATCH[2]}"
            fan_alarm=""

            [[ "${BASH_REMATCH[3]}" == *"ALARM"* ]] &&
                fan_alarm="ALARM"

            FANS_DATA+=(
                "${fan_name}|${fan_value}|${fan_alarm}"
            )

        fi

    done <<<"$output"

}

fans_analyze() {

    FANS_STATUS="${SW_STATUS_OK}"

    if [[ "$FANS_AVAILABLE" != true ]]; then

        FANS_STATUS="${SW_STATUS_UNKNOWN}"

        return

    fi

    # -------------------------------------------------------------------------
    # Fan alarms are informational.
    #
    # An ALARM does not automatically mean WARNING or CRITICAL because an
    # unused motherboard fan header can legitimately report 0 RPM + ALARM.
    # -------------------------------------------------------------------------

}

fans_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "$(sw_translate "Fans")"
    sw_state_set "module.icon" "lucide/fan"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Availability
    # -------------------------------------------------------------------------

    sw_state_set "available" "${FANS_AVAILABLE}"

    # -------------------------------------------------------------------------
    # Fans
    # -------------------------------------------------------------------------

    local fan
    local fan_name
    local fan_value
    local fan_alarm

    for fan in "${FANS_DATA[@]}"; do

        IFS='|' read -r fan_name fan_value fan_alarm <<<"$fan"

        sw_state_set \
            "fan.${fan_name}" \
            "${fan_value}"

        sw_state_set \
            "fan.${fan_name}.label" \
            "${fan_name}"

        if [ "$fan_value" == "0" ]; then

            sw_state_set \
                "fan.${fan_name}.widget" \
                "value"

        else

            sw_state_set \
                "fan.${fan_name}.widget" \
                "line"
        fi

        sw_state_set \
            "fan.${fan_name}.unit" \
            "RPM"

        sw_state_set \
            "fan.${fan_name}.order" \
            "$((10 + ${fan_name#fan} * 10))"

        if [[ "$fan_alarm" == "ALARM" ]]; then

            sw_state_set \
                "fan.${fan_name}.alarm" \
                "true"

            sw_state_set \
                "fan.${fan_name}.alarm.label" \
                "fan ${fan_name} Alarm"

        fi

    done

}

fans_report() {

    if [[ "$FANS_AVAILABLE" != true ]]; then

        sw_log_info \
            "${MODULE_NAME}" \
            "sensors command unavailable"

        return

    fi

    local message="Fans"

    local fan
    local fan_name
    local fan_value
    local fan_alarm

    for fan in "${FANS_DATA[@]}"; do

        IFS='|' read -r fan_name fan_value fan_alarm <<<"$fan"

        message+=" | ${fan_name}: ${fan_value} RPM"

        [[ "$fan_alarm" == "ALARM" ]] &&
            message+=" ALARM"

    done

    sw_log_info \
        "${MODULE_NAME}" \
        "${message} (${FANS_STATUS})"

}

# -----------------------------------------------------------------------------
# Module entry point
# -----------------------------------------------------------------------------

sw_module_run() {

    sw_state_use "fans"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    fans_collect

    fans_analyze

    sw_status_update "${FANS_STATUS}" || return 1

    fans_update_state

    sw_state_save

    # -------------------------------------------------------------------------
    # CSV history
    # -------------------------------------------------------------------------

    local fan
    local fan_name
    local fan_value
    local fan_alarm

    for fan in "${FANS_DATA[@]}"; do

        IFS='|' read -r fan_name fan_value fan_alarm <<<"$fan"

        sw_csv_append \
            "fans" \
            "fan.${fan_name}" \
            "${fan_value}"

    done

    fans_report

}
