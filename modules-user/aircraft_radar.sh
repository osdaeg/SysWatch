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
readonly MODULE_DESCRIPTION="Show aircraft radar"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-180}
MODULE_ORDER=${MODULE_ORDER:-1200}
MODULE_REMOTE=${MODULE_REMOTE:-""}


# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

AIRCRAFT_RADAR_STATUS="${SW_STATUS_UNKNOWN}"
AIRCRAFT_BASE_MAP="aircraft_map_base_${WEATHER_LAT}_${WEATHER_LON}.png"

MODULE_INTERVAL_IF_AIRCRAFTS=30


aircraft_radar_collect() {

    local opensky_file
    local generated_map_file
    local basemap_file

    local current_lat="${WEATHER_LAT}"
    local current_lon="${WEATHER_LON}"

    local saved_lat
    local saved_lon

    saved_lat="$(sw_state_get "map.latitude")"
    saved_lon="$(sw_state_get "map.longitude")"

    opensky_file="$(sw_cache_file "opensky.json")"
    generated_map_file="$(sw_cache_file "aircraft_map_base.png")"
    basemap_file="$(sw_cache_file "${AIRCRAFT_BASE_MAP}")"

    # No OpenSky data: nothing to render.
    if ! sw_cache_exists "opensky.json"; then
        return 1
    fi

    if [[ "${saved_lat}" != "${current_lat}" ||
      "${saved_lon}" != "${current_lon}" ]]; then
        if sw_cache_exists "${AIRCRAFT_BASE_MAP}"; then
            cp "${basemap_file}" "${generated_map_file}"
        else    
            sw_cache_remove "aircraft_map_base.png"
            python3 "${HELPERS_DIR}/aircraft_radar.py" || return 1
        fi    
    fi

    if jq -e '.states and (.states | length > 0)' \
        "${opensky_file}" >/dev/null 2>&1; then

        # Aircraft available: render the radar.
        python3 "${HELPERS_DIR}/aircraft_radar.py" || return 1

        # Python generated the current base map.
        cp "${generated_map_file}" "${basemap_file}" || return 1

        AIRCRAFT_RADAR_STATUS="${SW_STATUS_INFO}"

        MODULE_INTERVAL=$MODULE_INTERVAL_IF_AIRCRAFTS

    elif sw_cache_exists "${AIRCRAFT_BASE_MAP}"; then

        # No aircraft: show the cached base map for this location.
        cp "${basemap_file}" \
           "${HTML_DIR}/images/mapa_aviones.png" || return 1

        AIRCRAFT_RADAR_STATUS="${SW_STATUS_OK}"

        MODULE_INTERVAL=180

    else

        # No aircraft and no base map for this location.
        # Let Python create the initial base map.
        python3 "${SCRIPT_DIR}/aircraft_radar.py" || return 1

        cp "${generated_map_file}" "${basemap_file}" || return 1
        cp "${basemap_file}" \
           "${HTML_DIR}/images/mapa_aviones.png" || return 1

        AIRCRAFT_RADAR_STATUS="${SW_STATUS_OK}"
    fi
}

aircraft_radar_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata (consumed by lib/html.sh)
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "Aircraft Radar"
    sw_state_set "module.icon" "lucide/plane"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Data
    # -------------------------------------------------------------------------

    sw_state_set "image" "mapa_aviones.png"

    sw_state_set "image.label" "Radar de aviones"
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

    if (( result == 1 )); then
        sw_log_info \
            "${MODULE_NAME}" \
            "Datos no generados"
        AIRCRAFT_RADAR_STATUS="${SW_STATUS_WARNING}"   
    fi

    if (( result != 0 )); then
        return "${result}"
    fi

    sw_status_update "${AIRCRAFT_RADAR_STATUS}" || return 1

    aircraft_radar_update_state
    sw_state_save
}
