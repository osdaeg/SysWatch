#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Aircraft radar
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Aircraft Radar"
readonly MODULE_SCRIPT="$(realpath "${BASH_SOURCE[0]}")"
readonly MODULE_DESCRIPTION="Show aircraft radar"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-180}
MODULE_INTERVAL_NORMAL=${MODULE_INTERVAL_NORMAL:-}
MODULE_INTERVAL_ALT=${MODULE_INTERVAL_ALT:-}
MODULE_ORDER=${MODULE_ORDER:-1200}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

AIRCRAFT_RADAR_STATUS="${SW_STATUS_UNKNOWN}"
AIRCRAFT_BASE_MAP="aircraft_map_base_${WEATHER_LAT}_${WEATHER_LON}.png"
AIRCRAFT_BASE_MAP_GRAYSCALE="aircraft_map_base_${WEATHER_LAT}_${WEATHER_LON}_grayscale.png"

MODULE_INTERVAL_IF_AIRCRAFTS="$MODULE_INTERVAL_ALT"

aircraft_radar_collect() {

    local opensky_file
    local generated_map_file
    local generated_grayscale_file
    local basemap_file
    local grayscale_basemap_file
    opensky_file="$(sw_cache_file "opensky.json")"
    generated_map_file="$(sw_cache_file "aircraft_map_base.png")"
    generated_grayscale_file="$(sw_cache_file "aircraft_map_base_grayscale.png")"
    basemap_file="$(sw_cache_file "${AIRCRAFT_BASE_MAP}")"
    grayscale_basemap_file="$(sw_cache_file "${AIRCRAFT_BASE_MAP_GRAYSCALE}")"

    # No OpenSky data: nothing to render.
    if ! sw_cache_exists "opensky.json"; then
        return 1
    fi

    # Restore the base maps for the configured coordinates before Python
    # checks their age. Preserve timestamps so AIRCRAFT_MAP_REFRESH_DAYS works.
    if sw_cache_exists "${AIRCRAFT_BASE_MAP}"; then
        cp -p "${basemap_file}" "${generated_map_file}" || return 1
    else
        sw_cache_remove "aircraft_map_base.png"
    fi

    if sw_cache_exists "${AIRCRAFT_BASE_MAP_GRAYSCALE}"; then
        cp -p "${grayscale_basemap_file}" "${generated_grayscale_file}" || return 1
    else
        sw_cache_remove "aircraft_map_base_grayscale.png"
    fi

    python3 "${HELPERS_DIR}/aircraft_radar.py" || return 1

    # Save each style's base map in its location-specific cache.
    if [[ -f "${generated_map_file}" ]]; then
        cp -p "${generated_map_file}" "${basemap_file}" || return 1
    fi

    if [[ -f "${generated_grayscale_file}" ]]; then
        cp -p "${generated_grayscale_file}" "${grayscale_basemap_file}" || return 1
    fi

    if jq -e '.states and (.states | length > 0)' \
        "${opensky_file}" >/dev/null 2>&1; then
        AIRCRAFT_RADAR_STATUS="${SW_STATUS_INFO}"
        MODULE_INTERVAL=$MODULE_INTERVAL_ALT
        #cp "${HTML_DIR}/images/mapa_aviones.png" "${CACHE_DIR}/$(date +%s).png"
    else
        AIRCRAFT_RADAR_STATUS="${SW_STATUS_OK}"
        MODULE_INTERVAL="$MODULE_INTERVAL_NORMAL"
    fi
}

aircraft_radar_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata (consumed by lib/html.sh)
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "$(sw_translate "Aircraft Radar")"
    sw_state_set "module.icon" "lucide/plane"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Data
    # -------------------------------------------------------------------------

    sw_state_set "image" "mapa_aviones.png"

    sw_state_set "image.label" "$(sw_translate "Aircraft Radar")"
    sw_state_set "image.widget" "image"
    sw_state_set "image.unit" ""
    sw_state_set "image.order" "10"
    sw_state_set "map.latitude" "${WEATHER_LAT}"
    sw_state_set "map.longitude" "${WEATHER_LON}"
    sw_state_set "map.latitude.hidden" "true"
    sw_state_set "map.longitude.hidden" "true"

}

aircraft_radar_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Radar generado correctamente (${AIRCRAFT_RADAR_STATUS})"

}

sw_module_run() {
    sw_state_use "aircraft_radar"
    sw_state_load

    aircraft_radar_collect
    local result=$?

    if ((result == 1)); then
        sw_log_info \
            "${MODULE_NAME}" \
            "Datos no generados"
        AIRCRAFT_RADAR_STATUS="${SW_STATUS_WARNING}"
    fi

    if ((result != 0)); then
        return "${result}"
    fi

    sw_status_update "${AIRCRAFT_RADAR_STATUS}" || return 1

    aircraft_radar_update_state
    sw_state_save
}
