#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# voltages module
#
# Reports hardware voltage sensors with known meanings.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Voltages"
readonly MODULE_DESCRIPTION="Hardware voltage sensors"
readonly MODULE_VERSION="0.1.0"

MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-1180}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

VOLTAGES_STATUS="${SW_STATUS_UNKNOWN}"

VOLTAGES_AVAILABLE=false

VOLTAGES_3V3=""
VOLTAGES_3VSB=""
VOLTAGES_5VSB=""
VOLTAGES_VBAT=""

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

voltages_collect() {

    VOLTAGES_STATUS="${SW_STATUS_UNKNOWN}"

    VOLTAGES_AVAILABLE=false

    VOLTAGES_3V3=""
    VOLTAGES_3VSB=""
    VOLTAGES_5VSB=""
    VOLTAGES_VBAT=""

    command -v sensors >/dev/null 2>&1 || return 0

    local output

    output="$(sensors 2>/dev/null)" || return 0

    [[ -n "$output" ]] || return 0

    local line

    while IFS= read -r line; do

        # ---------------------------------------------------------------------
        # +3.3V
        # ---------------------------------------------------------------------

        if [[ "$line" =~ ^\+3\.3V:[[:space:]]*([0-9.]+)[[:space:]]*V ]]; then

            VOLTAGES_3V3="${BASH_REMATCH[1]}"
            VOLTAGES_AVAILABLE=true

            continue

        fi

        # ---------------------------------------------------------------------
        # 3VSB
        # ---------------------------------------------------------------------

        if [[ "$line" =~ ^3VSB:[[:space:]]*([0-9.]+)[[:space:]]*V ]]; then

            VOLTAGES_3VSB="${BASH_REMATCH[1]}"
            VOLTAGES_AVAILABLE=true

            continue

        fi

        # ---------------------------------------------------------------------
        # 5VSB
        # ---------------------------------------------------------------------

        if [[ "$line" =~ ^5VSB:[[:space:]]*([0-9.]+)[[:space:]]*V ]]; then

            VOLTAGES_5VSB="${BASH_REMATCH[1]}"
            VOLTAGES_AVAILABLE=true

            continue

        fi

        # ---------------------------------------------------------------------
        # Battery voltage
        # ---------------------------------------------------------------------

        if [[ "$line" =~ ^Vbat:[[:space:]]*([0-9.]+)[[:space:]]*V ]]; then

            VOLTAGES_VBAT="${BASH_REMATCH[1]}"
            VOLTAGES_AVAILABLE=true

            continue

        fi

    done <<<"$output"

}

voltages_analyze() {

    if [[ "$VOLTAGES_AVAILABLE" != true ]]; then

        VOLTAGES_STATUS="${SW_STATUS_UNKNOWN}"

        return

    fi

    # -------------------------------------------------------------------------
    # No automatic WARNING/CRITICAL evaluation for now.
    #
    # The available sensor output does not provide reliable limits for all
    # reported voltages.
    # -------------------------------------------------------------------------

    VOLTAGES_STATUS="${SW_STATUS_OK}"

}

voltages_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "$(sw_translate "Voltages")"
    sw_state_set "module.icon" "lucide/plug"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Availability
    # -------------------------------------------------------------------------

    sw_state_set "available" "${VOLTAGES_AVAILABLE}"

    # -------------------------------------------------------------------------
    # +3.3V
    # -------------------------------------------------------------------------

    if [[ -n "$VOLTAGES_3V3" ]]; then

        sw_state_set "3v3" "${VOLTAGES_3V3}"
        sw_state_set "3v3.label" "$(sw_translate "+3.3V")"
        sw_state_set "3v3.widget" "value"
        sw_state_set "3v3.unit" "V"
        sw_state_set "3v3.order" "10"

    fi

    # -------------------------------------------------------------------------
    # 3VSB
    # -------------------------------------------------------------------------

    if [[ -n "$VOLTAGES_3VSB" ]]; then

        sw_state_set "3vsb" "${VOLTAGES_3VSB}"
        sw_state_set "3vsb.label" "$(sw_translate "3VSB")"
        sw_state_set "3vsb.widget" "value"
        sw_state_set "3vsb.unit" "V"
        sw_state_set "3vsb.order" "20"

    fi

    # -------------------------------------------------------------------------
    # 5VSB
    # -------------------------------------------------------------------------

    if [[ -n "$VOLTAGES_5VSB" ]]; then

        sw_state_set "5vsb" "${VOLTAGES_5VSB}"
        sw_state_set "5vsb.label" "$(sw_translate "5VSB")"
        sw_state_set "5vsb.widget" "value"
        sw_state_set "5vsb.unit" "V"
        sw_state_set "5vsb.order" "30"

    fi

    # -------------------------------------------------------------------------
    # Battery
    # -------------------------------------------------------------------------

    if [[ -n "$VOLTAGES_VBAT" ]]; then

        sw_state_set "vbat" "${VOLTAGES_VBAT}"
        sw_state_set "vbat.label" "$(sw_translate "Vbat")"
        sw_state_set "vbat.widget" "value"
        sw_state_set "vbat.unit" "V"
        sw_state_set "vbat.order" "40"

    fi

}

voltages_report() {

    if [[ "$VOLTAGES_AVAILABLE" != true ]]; then

        sw_log_info \
            "${MODULE_NAME}" \
            "voltage sensors unavailable"

        return

    fi

    local message="Voltages"

    [[ -n "$VOLTAGES_3V3" ]] &&
        message+=" | +3.3V: ${VOLTAGES_3V3} V"

    [[ -n "$VOLTAGES_3VSB" ]] &&
        message+=" | 3VSB: ${VOLTAGES_3VSB} V"

    [[ -n "$VOLTAGES_5VSB" ]] &&
        message+=" | 5VSB: ${VOLTAGES_5VSB} V"

    [[ -n "$VOLTAGES_VBAT" ]] &&
        message+=" | Vbat: ${VOLTAGES_VBAT} V"

    sw_log_info \
        "${MODULE_NAME}" \
        "${message} (${VOLTAGES_STATUS})"

}

# -----------------------------------------------------------------------------
# Module entry point
# -----------------------------------------------------------------------------

sw_module_run() {

    sw_state_use "voltages"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    voltages_collect

    voltages_analyze

    sw_status_update "${VOLTAGES_STATUS}" || return 1

    voltages_update_state

    sw_state_save

    voltages_report

}
