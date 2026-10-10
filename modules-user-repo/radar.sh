#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# RainViewer radar module
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Radar"
readonly MODULE_DESCRIPTION="RainViewer weather radar"
readonly MODULE_VERSION="0.1.0"

MODULE_INTERVAL=${MODULE_INTERVAL:-600}
MODULE_ORDER=${MODULE_ORDER:-120}

MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

RADAR_STATUS="${SW_STATUS_UNKNOWN}"
RADAR_FILE=""

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------

readonly RADAR_SCRIPT="${HELPERS_DIR}/rainviewer.py"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

radar_collect() {

    RADAR_STATUS="${SW_STATUS_UNKNOWN}"

    if [[ ! -f "$RADAR_SCRIPT" ]]; then
        sw_log_error \
            "${MODULE_NAME}" \
            "No se encontró rainviewer.py: ${RADAR_SCRIPT}"

        RADAR_STATUS="${SW_STATUS_CRITICAL}"
        return
    fi

    if ! env \
        WEATHER_LAT="$WEATHER_LAT" \
        WEATHER_LON="$WEATHER_LON" \
        CACHE_DIR="$CACHE_DIR" \
        HTML_DIR="$HTML_DIR" \
        python3 "$RADAR_SCRIPT"
    then

        sw_log_error \
            "${MODULE_NAME}" \
            "Falló la ejecución de rainviewer.py"

        RADAR_STATUS="${SW_STATUS_CRITICAL}"
        return
    fi

    RADAR_FILE="${HTML_DIR}/radar.png"

    if [[ ! -s "$RADAR_FILE" ]]; then

        sw_log_error \
            "${MODULE_NAME}" \
            "RainViewer no generó ${RADAR_FILE}"

        RADAR_STATUS="${SW_STATUS_CRITICAL}"
        return
    fi

    RADAR_STATUS="${SW_STATUS_OK}"
}

radar_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "$(sw_translate "Radar")"
    sw_state_set "module.icon" "lucide/radar"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Data
    # -------------------------------------------------------------------------

    sw_state_set "status" "${RADAR_STATUS}"

    sw_state_set "radar.label" "$(sw_translate "Radar")"
    sw_state_set "radar.value" "RainViewer"
    sw_state_set "radar.order" "10"

}

radar_report() {

    if [[ "$RADAR_STATUS" == "$SW_STATUS_OK" ]]; then

        sw_log_info \
            "${MODULE_NAME}" \
            "Radar RainViewer actualizado correctamente."

    else

        sw_log_error \
            "${MODULE_NAME}" \
            "No se pudo actualizar el radar RainViewer."

    fi

}

sw_module_run() {

    sw_state_use "radar"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    radar_collect

    sw_status_update "${RADAR_STATUS}" || return 1

    radar_update_state

    sw_state_save

    radar_report

}