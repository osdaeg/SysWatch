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

radar_debug() {

    local size

    if [[ ! -f "$RADAR_FILE" ]]; then
        sw_log_error \
            "${MODULE_NAME}" \
            "DEBUG: radar.png no existe."

        return
    fi

    size="$(stat -c '%s' "$RADAR_FILE")"

    sw_log_info \
        "${MODULE_NAME}" \
        "DEBUG: radar.png existe (${size} bytes)."

    python3 - "$RADAR_FILE" <<'PY'
from PIL import Image
import sys

image = Image.open(sys.argv[1]).convert("RGBA")
alpha = image.getchannel("A")

print(f"DEBUG: tamaño={image.size}")
print(f"DEBUG: alpha={alpha.getextrema()}")

if alpha.getbbox() is None:
    print("DEBUG: imagen completamente transparente")
else:
    print(f"DEBUG: contenido visible={alpha.getbbox()}")
PY
}

radar_collect() {

    local radar

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

    RADAR_FILE="${HTML_DIR}/images/radar.png"

    if [[ ! -s "$RADAR_FILE" ]]; then

        sw_log_error \
            "${MODULE_NAME}" \
            "RainViewer no generó ${RADAR_FILE}"

        RADAR_STATUS="${SW_STATUS_CRITICAL}"
        return
    fi

    radar_debug >> "${CACHE_DIR}/radar_debug.log" 2>&1

    #radar="$(sw_csv_last_values "weather" "radar" "1")"

    sw_message_load "weather"

    radar="$MESSAGE_FROM_MODULE"

    if [[ -n "$radar" ]]; then
        if [[ "$radar" == "1" ]]; then
            RADAR_STATUS="${SW_STATUS_CRITICAL}"
            MODULE_ORDER=2
            MODULE_INTERVAL=30
        else
            RADAR_STATUS="${SW_STATUS_OK}"
            MODULE_ORDER=9000
            MODULE_INTERVAL=3660
        fi
    else
        RADAR_STATUS="${SW_STATUS_OK}"
        MODULE_ORDER=9000
        MODULE_INTERVAL=3660
    fi
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

    sw_state_set "image" "radar.png"

    sw_state_set "image.label" "$(sw_translate "Radar image")"
    sw_state_set "image.widget" "image"
    sw_state_set "image.unit" ""
    sw_state_set "image.order" "20"
    #sw_state_set "image.warning" "${APOD_WARNING}"
    #sw_state_set "image.critical" "${APOD_CRITICAL}"

    sw_state_set "status" "${RADAR_STATUS}"

    sw_state_set "radar.label" "$(sw_translate "Radar")"
    sw_state_set "radar" "RainViewer"
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