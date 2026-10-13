#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# power module
#
# Reports hardware power consumption.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Power"
readonly MODULE_DESCRIPTION="Hardware power consumption"
readonly MODULE_VERSION="0.1.0"

MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-1150}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly POWER_WARNING="${POWER_WARNING:-80}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

POWER_STATUS="${SW_STATUS_UNKNOWN}"

POWER_AVAILABLE=false

POWER_CURRENT=""
POWER_AVG=""
POWER_CRITICAL=""

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

power_collect() {

    POWER_STATUS="${SW_STATUS_UNKNOWN}"

    POWER_AVAILABLE=false

    POWER_CURRENT=""
    POWER_AVG=""
    POWER_CRITICAL=""

    command -v sensors >/dev/null 2>&1 || return 0

    local output

    output="$(sensors 2>/dev/null)" || return 0

    [[ -n "$output" ]] || return 0

    POWER_AVAILABLE=true

    local line

    while IFS= read -r line; do

        # ---------------------------------------------------------------------
        # Current power and average
        # ---------------------------------------------------------------------

        if [[ "$line" =~ ^power[0-9]+:[[:space:]]*([0-9.]+)[[:space:]]*mW[[:space:]]*\(avg[[:space:]]*=[[:space:]]*([0-9.]+)[[:space:]]*mW ]]; then

            POWER_CURRENT="${BASH_REMATCH[1]}"
            POWER_AVG="${BASH_REMATCH[2]}"

            continue

        fi

        # ---------------------------------------------------------------------
        # Critical power limit
        # ---------------------------------------------------------------------

        if [[ "$line" =~ ^power[0-9]+:[[:space:]]*.*\(crit[[:space:]]*=[[:space:]]*([0-9.]+)[[:space:]]*W ]]; then

            POWER_CRITICAL="${BASH_REMATCH[1]}"

            continue

        fi

    done <<<"$output"

}

power_analyze() {

    POWER_STATUS="${SW_STATUS_OK}"

    if [[ "$POWER_AVAILABLE" != true ]]; then

        POWER_STATUS="${SW_STATUS_UNKNOWN}"

        return

    fi

    [[ -n "$POWER_CURRENT" ]] || return

    # -------------------------------------------------------------------------
    # Power reported by sensors is mW.
    # Critical threshold is reported in W.
    #
    # Warning threshold is a percentage of the critical threshold.
    # -------------------------------------------------------------------------

    if [[ -n "$POWER_CRITICAL" ]]; then

        local power_w
        local warning_w

        power_w="$(awk \
            -v value="$POWER_CURRENT" \
            'BEGIN { printf "%.3f", value / 1000 }')"

        warning_w="$(awk \
            -v crit="$POWER_CRITICAL" \
            -v percent="$POWER_WARNING" \
            'BEGIN { printf "%.3f", crit * percent / 100 }')"

        if awk \
            -v value="$power_w" \
            -v crit="$POWER_CRITICAL" \
            'BEGIN { exit !(value >= crit) }'; then

            POWER_STATUS="${SW_STATUS_CRITICAL}"

        elif awk \
            -v value="$power_w" \
            -v warning="$warning_w" \
            'BEGIN { exit !(value >= warning) }'; then

            POWER_STATUS="${SW_STATUS_WARNING}"

        fi

    fi

}

power_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "$(sw_translate "Power")"
    sw_state_set "module.icon" "lucide/zap"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Availability
    # -------------------------------------------------------------------------

    sw_state_set "available" "${POWER_AVAILABLE}"
    sw_state_set "available.hidden" "true"

    # -------------------------------------------------------------------------
    # Current power
    #
    # Keep the real sensor value here.
    # This is intentionally NOT a line widget.
    # -------------------------------------------------------------------------

    if [[ -n "$POWER_CURRENT" ]]; then

        sw_state_set "power_current" "${POWER_CURRENT}"
        sw_state_set "power_current.label" "$(sw_translate "Power")"
        sw_state_set "power_current.widget" "value"
        sw_state_set "power_current.unit" "mW"
        sw_state_set "power_current.order" "10"

    fi

    # -------------------------------------------------------------------------
    # Power history
    #
    # The line widget receives an integer value so html.sh can safely
    # perform arithmetic with it.
    # -------------------------------------------------------------------------

    if [[ -n "$POWER_CURRENT" ]]; then

        local power_csv

        power_csv="$(awk \
            -v value="$POWER_CURRENT" \
            'BEGIN { printf "%.0f", value }')"

        sw_state_set "power" "${power_csv}"
        sw_state_set "power.label" "$(sw_translate "Power history")"
        sw_state_set "power.widget" "line"
        sw_state_set "power.unit" "mW"
        sw_state_set "power.order" "20"

    fi

    # -------------------------------------------------------------------------
    # Average power
    # -------------------------------------------------------------------------

    if [[ -n "$POWER_AVG" ]]; then

        sw_state_set "power_avg" "${POWER_AVG}"
        sw_state_set "power_avg.label" "$(sw_translate "Power average")"
        sw_state_set "power_avg.widget" "value"
        sw_state_set "power_avg.unit" "mW"
        sw_state_set "power_avg.order" "30"

    fi

    # -------------------------------------------------------------------------
    # Critical threshold
    # -------------------------------------------------------------------------

    if [[ -n "$POWER_CRITICAL" ]]; then

        local critical_mw

        critical_mw="$(awk \
            -v value="$POWER_CRITICAL" \
            'BEGIN { printf "%.0f", value * 1000 }')"

        sw_state_set "power.critical" "${critical_mw}"

    fi

}

power_report() {

    if [[ "$POWER_AVAILABLE" != true ]]; then

        sw_log_info \
            "${MODULE_NAME}" \
            "sensors command unavailable"

        return

    fi

    local message="Power"

    [[ -n "$POWER_CURRENT" ]] &&
        message+=": ${POWER_CURRENT} mW"

    [[ -n "$POWER_AVG" ]] &&
        message+=" | Avg: ${POWER_AVG} mW"

    sw_log_info \
        "${MODULE_NAME}" \
        "${message} (${POWER_STATUS})"

}

# -----------------------------------------------------------------------------
# Module entry point
# -----------------------------------------------------------------------------

sw_module_run() {

    sw_state_use "power"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    power_collect

    power_analyze

    sw_status_update "${POWER_STATUS}" || return 1

    power_update_state

    sw_state_save

    # -------------------------------------------------------------------------
    # CSV history
    # -------------------------------------------------------------------------

    if [[ -n "$POWER_CURRENT" ]]; then

        local power_csv

        power_csv="$(awk \
            -v value="$POWER_CURRENT" \
            'BEGIN { printf "%.0f", value }')"

        sw_csv_append \
            "power" \
            "power" \
            "${power_csv}"

    fi

    power_report

}
