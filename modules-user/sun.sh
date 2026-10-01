#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# module template
#
# Copy this file into modules-user/ or modules-root/, rename it, and replace
# every "SUN"/"moon" placeholder with your module's name.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Sun"
readonly MODULE_DESCRIPTION="Sun events"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-660}
MODULE_ORDER=${MODULE_ORDER:-1001}
MODULE_REMOTE=${MODULE_REMOTE:-""}


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly SUN_WARNING="${SUN_WARNING:-80}"
readonly SUN_CRITICAL="${SUN_CRITICAL:-95}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

SUN_VALUE=0
SUN_STATUS="${SW_STATUS_UNKNOWN}"
SUN_CACHE="moon.json"
SUN_EVENTS_CACHE="moon-events.json"
SUN_IMAGE_CACHE="latest_1024_0193.jpg"

SUN_CACHE="sun.json"
SUN_EVENTS_CACHE="sun-events.json"

CACHE_MINUTES=120
CACHE_EVENTS_MINUTES=10080

SUN_PHASE=""
SUN_ILLUMINATION=""
SUN_CONSTELLATION=""
SUN_DISTANCE=""
SUN_DISTANCE_KM=""
SUN_ALTITUDE=""
SUN_AZIMUTH=""
SUN_RA=""
SUN_DEC=""
SUN_MAGNITUDE=""
SUN_ELONGATION=""
SUN_EVENT_TYPE=""
SUN_EVENT_DATE=""
SUN_RISE=""
SUN_SET=""
SUN_OBSCURATION=""
SUN_SUPER=""

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

sun_format_date() {

    [[ -n "$1" ]] || return

    date -d "$1" "+%d/%m/%Y - %H:%M:%S"

}

sun_event_name() {
    case "$1" in
        partial_solar_eclipse)
            echo "$(sw_translate "Partial solar eclipse")"
            ;;
        annular_solar_eclipse)
            echo "$(sw_translate "Annular solar eclipse")"
            ;;    
        total_solar_eclipse)
            echo "$(sw_translate "Total solar eclipse")"
            ;;
        *)
            echo "$1"
            ;;
    esac
}


sun_fetch() {

    local url

    if sw_cache_is_expired "${SUN_CACHE}" "${CACHE_MINUTES}"; then

        sw_log_debug "Updating sun position..."

        url="https://api.astronomyapi.com/api/v2/bodies/positions/sun"

        sw_cache_download \
            "${SUN_CACHE}" \
            "${url}?latitude=${WEATHER_LAT}&longitude=${WEATHER_LON}&elevation=0&from_date=$(date +%F)&to_date=$(date +%F)&time=$(date +%T)" \
            --user "${ASTRONOMY_API_ID}:${ASTRONOMY_API_SECRET}" \
            || return 1

    fi

    if sw_cache_is_expired "${SUN_EVENTS_CACHE}" "${CACHE_EVENTS_MINUTES}"; then

        sw_log_debug "Updating sun events..."

        url="https://api.astronomyapi.com/api/v2/bodies/events/sun"

        sw_cache_download \
            "${SUN_EVENTS_CACHE}" \
            "${url}?latitude=${WEATHER_LAT}&longitude=${WEATHER_LON}&elevation=0&from_date=$(date +%F)&to_date=$(date -d '+365 days' +%F)&time=$(date +%H%%3A%M%%3A%S)" \
            --user "${ASTRONOMY_API_ID}:${ASTRONOMY_API_SECRET}" \
            || return 1

    fi

    if sw_cache_is_expired "${SUN_IMAGE_CACHE}" "${CACHE_MINUTES}"; then

        sw_log_debug "Updating sun image..."

        url="https://sdo.gsfc.nasa.gov/assets/img/latest/latest_1024_0193.jpg"

        sw_cache_download \
            "${SUN_IMAGE_CACHE}" \
            "${url}" \
            || return 1

        cp "$(sw_cache_file "${SUN_IMAGE_CACHE}")" "${HTML_DIR}/images/sol.jpg"    

    fi

}

sun_analyze_position() {

    local file

    file="$(sw_cache_file "${SUN_CACHE}")"

    IFS='|' read -r \
        SUN_CONSTELLATION \
        SUN_DISTANCE \
        SUN_ALTITUDE \
        SUN_AZIMUTH \
        SUN_RA \
        SUN_DEC \
        SUN_MAGNITUDE \
        SUN_ELONGATION \
    <<<"$(
        jq -r '
        .data.table.rows[0].cells[0] |
        [
            .position.constellation.name,
            .distance.fromEarth.km,
            .position.horizontal.altitude.degrees,
            .position.horizontal.azimuth.degrees,
            .position.equatorial.rightAscension.string,
            .position.equatorial.declination.string,
            .extraInfo.magnitude,
            .extraInfo.elongation
        ] | join("|")
        ' "${file}"
    )" || return 1

    SUN_DISTANCE_KM="${SUN_DISTANCE%.*}"
    SUN_DISTANCE="$(sw_format_number "${SUN_DISTANCE_KM}")"
    SUN_ALTITUDE="${SUN_ALTITUDE%.*}"
    SUN_AZIMUTH="${SUN_AZIMUTH%.*}"

}

sun_analyze_events() {

    local file

    file="$(sw_cache_file "${SUN_EVENTS_CACHE}")"

    if [[ "$(jq '.data.table.rows[0].cells | length' "${file}")" -eq 0 ]]; then
        SUN_EVENT_TYPE=""
        SUN_EVENT_DATE=""
        SUN_RISE=""
        SUN_SET=""
        SUN_OBSCURATION=""
        return 0
    fi

    IFS='|' read -r \
        SUN_EVENT_TYPE \
        SUN_EVENT_DATE \
        SUN_RISE \
        SUN_SET \
        SUN_OBSCURATION \
    <<<"$(
        jq -r '
        .data.table.rows[0].cells[0] |
        [
            .type,
            .eventHighlights.peak.date,
            .rise,
            .set,
            .extraInfo.obscuration
        ] | join("|")
        ' "${file}"
    )" || return 1

}

sun_update_status() {

    local timestamp1=""
    local timestamp2=""

    SUN_STATUS="${SW_STATUS_OK}"

    if [[ -n "${SUN_EVENT_DATE}" ]]; then
        timestamp1="$(date -d "${SUN_EVENT_DATE}" +%F)"
        timestamp2="$(date +%F)"

        if [[ "${timestamp1}" == "${timestamp2}" ]]; then
            SUN_STATUS="${SW_STATUS_CRITICAL}"
        fi
    fi
    
    
}

sun_analyze() {

    sun_analyze_position || return 1

    sun_analyze_events || return 1

    sun_update_status

}

sun_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.icon" "lucide/sun"
    sw_state_set "module.label" "$(sw_translate "Sun")"
    sw_state_set "module.order" "$MODULE_ORDER"
    
    sw_state_set "constellation" "$(sw_zodiac_emoji $SUN_CONSTELLATION) ${SUN_CONSTELLATION}"
    sw_state_set "constellation.label" "$(sw_translate "Constellation")"
    sw_state_set "constellation.order" "20"

    sw_state_set "distance" "${SUN_DISTANCE}"
    sw_state_set "distance.label" "$(sw_translate "Distance")"
    sw_state_set "distance.unit" "km"
    sw_state_set "distance.order" "30"

    sw_state_set "altitude" "${SUN_ALTITUDE}"
    sw_state_set "altitude.label" "$(sw_translate "Altitude")"
    sw_state_set "altitude.unit" "°"
    sw_state_set "altitude.order" "40"
    sw_state_set "altitude.hidden" "true"

    sw_state_set "azimuth" "${SUN_AZIMUTH}"
    sw_state_set "azimuth.label" "$(sw_translate "Azimuth")"
    sw_state_set "azimuth.unit" "°"
    sw_state_set "azimuth.order" "50"
    sw_state_set "azimuth.hidden" "true"

    if [[ -n "${SUN_EVENT_TYPE}" ]]; then
        sw_state_set "next_event" "$(sun_event_name "${SUN_EVENT_TYPE}")"
        sw_state_set "next_event.label" "$(sw_translate "Next event")"
        sw_state_set "next_event.order" "60"
        sw_state_set "next_event_date" "$(sun_format_date "${SUN_EVENT_DATE}")"
        sw_state_set "next_event_date.label" "$(sw_translate "Date")"
        sw_state_set "next_event_date.order" "70"
        sw_state_set "next_event.hidden" "false"
        sw_state_set "next_event_date.hidden" "false"
    else
        sw_state_set "next_event.hidden" "true"
        sw_state_set "next_event_date.hidden" "true"
    fi
    
    sw_state_set "image" "sol.jpg"

    sw_state_set "image.label" " "
    sw_state_set "image.widget" "image"
    sw_state_set "image.unit" ""
    sw_state_set "image.order" "80"
    sw_state_set "image.warning" "${SUN_WARNING}"
    sw_state_set "image.critical" "${SUN_CRITICAL}"

    sw_state_set "moonrise" "${SUN_RISE}"
    sw_state_set "moonrise.hidden" "true"
    sw_state_set "moonset" "${SUN_SET}"
    sw_state_set "moonset.hidden" "true"

    sw_state_set "right_ascension" "${SUN_RA}"
    sw_state_set "right_ascension.hidden" "true"

    sw_state_set "declination" "${SUN_DEC}"
    sw_state_set "declination.hidden" "true"

    sw_state_set "magnitude" "${SUN_MAGNITUDE}"
    sw_state_set "magnitude.hidden" "true"

    sw_state_set "elongation" "${SUN_ELONGATION}"
    sw_state_set "elongation.hidden" "true"

    sw_state_set "obscuration" "${SUN_OBSCURATION}"
    sw_state_set "obscuration.hidden" "true"

}



sun_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Sun value: ${SUN_PHASE} (${SUN_STATUS})"

}

sw_module_run() {

    local module

    module="sun"

    sw_module_load_config "astronomy"

    sw_state_use "${module}"
    sw_state_load

    sun_fetch

    sun_analyze

    sw_status_update "${SUN_STATUS}" || return 1

    sun_update_state

    sw_state_save

    sun_report

}
