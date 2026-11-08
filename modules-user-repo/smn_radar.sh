#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# module template
#
# Copy this file into modules-user/ or modules-root/, rename it, and replace
# every "EXAMPLE"/"example" placeholder with your module's name.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="SMN Radar"
readonly MODULE_SCRIPT="$(realpath "${BASH_SOURCE[0]}")"
readonly MODULE_DESCRIPTION="Muestra una imagen animada del radar de Bolivar del SMN"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-480}
MODULE_INTERVAL_NORMAL=${MODULE_INTERVAL_NORMAL:-}
MODULE_INTERVAL_ALT=${MODULE_INTERVAL_ALT:-}
MODULE_ORDER=${MODULE_ORDER:-800}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly SMN_WARNING="${SMN_WARNING:-80}"
readonly SMN_CRITICAL="${SMN_CRITICAL:-95}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

SMN_NAME=""
SMN_EXT=""
SMN_STATUS="${SW_STATUS_UNKNOWN}"
SMN_PATH="/home/daniel/scripts/OpenSMN/radar_test/animation.gif"
SMN_VALUE=0

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

smn_radar_collect() {

    # Collect raw metrics here.
    # This step should not determine the module status.

    sw_cache_copy_image_to_htmldir "$SMN_PATH"

}

smn_radar_analyze() {

    SMN_STATUS="${SW_STATUS_OK}"

    sw_message_load "weather"

    radar="$MESSAGE_FROM_MODULE"

    if [[ -n "$radar" ]]; then
        if [[ "$radar" == "1" ]]; then
            SMN_STATUS="${SW_STATUS_CRITICAL}"
            MODULE_INTERVAL="$MODULE_INTERVAL_ALT"
        else
            SMN_STATUS="${SW_STATUS_OK}"
            MODULE_INTERVAL="$MODULE_INTERVAL_NORMAL"
        fi
    else
        SMN_STATUS="${SW_STATUS_OK}"
        MODULE_INTERVAL="$MODULE_INTERVAL_NORMAL"
    fi

}

smn_radar_update_state() {

    sw_country_flags_load

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata (consumed by lib/html.sh)
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "Radar SMN $(sw_country_flag "AR")"
    sw_state_set "module.icon" "lucide/radar"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Data
    # -------------------------------------------------------------------------

    sw_state_set "image" "animation.gif"

    sw_state_set "image.label" "$(sw_translate "Radar de Bolivar")"
    sw_state_set "image.widget" "image"
    sw_state_set "image.unit" ""
    sw_state_set "image.order" "10"
    sw_state_set "image.warning" "${SMN_WARNING}"
    sw_state_set "image.critical" "${SMN_CRITICAL}"

}

smn_radar_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "SMN value: ${SMN_NAME} (${SMN_STATUS})"

}

sw_module_run() {

    sw_state_use "smn_radar"
    sw_state_load

    smn_radar_collect

    smn_radar_analyze

    sw_status_update "${SMN_STATUS}" || return 1

    smn_radar_update_state

    sw_state_save

    smn_radar_report

    # Optional: append to CSV history for sparkline widgets.
    #
    # sw_csv_append \
    #     "example" \
    #     "value" \
    #     "${SMN_VALUE}"

}
