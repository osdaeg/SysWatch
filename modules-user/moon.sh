#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# module template
#
# Copy this file into modules-user/ or modules-root/, rename it, and replace
# every "MOON"/"moon" placeholder with your module's name.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Moon"
readonly MODULE_DESCRIPTION="Moon phases"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-660}
MODULE_ORDER=${MODULE_ORDER:-1000}
MODULE_REMOTE=${MODULE_REMOTE:-""}


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly MOON_WARNING="${MOON_WARNING:-80}"
readonly MOON_CRITICAL="${MOON_CRITICAL:-95}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

MOON_VALUE=0
MOON_STATUS="${SW_STATUS_UNKNOWN}"
MOON_CACHE="moon.json"
MOON_EVENTS_CACHE="moon-events.json"
MOON_IMAGE="moon-phase.png"

SUN_CACHE="sun.json"
SUN_EVENTS_CACHE="sun-events.json"

MOON_PHASE=""
MOON_ILLUMINATION=""
MOON_CONSTELLATION=""
MOON_DISTANCE=""
MOON_DISTANCE_KM=""
MOON_ALTITUDE=""
MOON_AZIMUTH=""
MOON_RA=""
MOON_DEC=""
MOON_MAGNITUDE=""
MOON_ELONGATION=""
MOON_EVENT_TYPE=""
MOON_EVENT_DATE=""
MOON_RISE=""
MOON_SET=""
MOON_OBSCURATION=""
MOON_SUPER=""

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

moon_format_date() {

    [[ -n "$1" ]] || return

    date -d "$1" "+%d/%m/%Y - %H:%M:%S"

}

moon_phase_name() {

    case "$1" in
        "New Moon")
            echo "🌑 $(sw_translate "New Moon")"
            ;;

        "Waxing Crescent")
            echo "🌒 $(sw_translate "Waxing Crescent")"
            ;;

        "First Quarter")
            echo "🌓 $(sw_translate "First Quarter")"
            ;;

        "Waxing Gibbous")
            echo "🌔 $(sw_translate "Waxing Gibbous")"
            ;;

        "Full Moon")
            echo "🌕 $(sw_translate "Full Moon")"
            ;;

        "Waning Gibbous")
            echo "🌖 $(sw_translate "Waning Gibbous")"
            ;;

        "Last Quarter")
            echo "🌗 $(sw_translate "Last Quarter")"
            ;;

        "Waning Crescent")
            echo "🌘 $(sw_translate "Waning Crescent")"
            ;;

        *)
            echo "$1"
            ;;
    esac

}

moon_phase_image() {

    case "$1" in
        "New Moon") echo "new_moon.png" ;;
        "Waxing Crescent") echo "waxing_crescent.png" ;;
        "First Quarter") echo "first_quarter.png" ;;
        "Waxing Gibbous") echo "waxing_gibbous.png" ;;
        "Full Moon") echo "full_moon.png" ;;
        "Waning Gibbous") echo "waning_gibbous.png" ;;
        "Last Quarter") echo "last_quarter.png" ;;
        "Waning Crescent") echo "waning_crescent.png" ;;
        *) echo "unknown.png" ;;
    esac

}

moon_event_name() {
    case "$1" in
        penumbral_lunar_eclipse)
            echo "$(sw_translate "Penumbral lunar eclipse")"
            ;;
        partial_lunar_eclipse)
            echo "$(sw_translate "Partial lunar eclipse")"
            ;;
        total_lunar_eclipse)
            echo "$(sw_translate "Total lunar eclipse")"
            ;;
        *)
            echo "$1"
            ;;
    esac
}


moon_fetch() {

    local url

    if sw_cache_is_expired "${MOON_CACHE}" "${CACHE_MINUTES}"; then

        sw_log_debug "Updating moon position..."

        url="https://api.astronomyapi.com/api/v2/bodies/positions/moon"

        sw_cache_download \
            "${MOON_CACHE}" \
            "${url}?latitude=${WEATHER_LAT}&longitude=${WEATHER_LON}&elevation=0&from_date=$(date +%F)&to_date=$(date +%F)&time=$(date +%T)" \
            --user "${ASTRONOMY_API_ID}:${ASTRONOMY_API_SECRET}" \
            || return 1

    fi

    if sw_cache_is_expired "${MOON_EVENTS_CACHE}" "${CACHE_EVENTS_MINUTES}"; then

        sw_log_debug "Updating moon events..."

        url="https://api.astronomyapi.com/api/v2/bodies/events/moon"

        sw_cache_download \
            "${MOON_EVENTS_CACHE}" \
            "${url}?latitude=${WEATHER_LAT}&longitude=${WEATHER_LON}&elevation=0&from_date=$(date +%F)&to_date=$(date -d '+30 days' +%F)&time=$(date +%H%%3A%M%%3A%S)" \
            --user "${ASTRONOMY_API_ID}:${ASTRONOMY_API_SECRET}" \
            || return 1

    fi

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

}

moon_analyze_position() {

    local file

    file="$(sw_cache_file "${MOON_CACHE}")"

    IFS='|' read -r \
        MOON_PHASE \
        MOON_CONSTELLATION \
        MOON_DISTANCE \
        MOON_ALTITUDE \
        MOON_AZIMUTH \
        MOON_RA \
        MOON_DEC \
        MOON_MAGNITUDE \
        MOON_ELONGATION \
    <<<"$(
        jq -r '
        .data.table.rows[0].cells[0] |
        [
            .extraInfo.phase.string,
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

    MOON_DISTANCE_KM="${MOON_DISTANCE%.*}"
    MOON_DISTANCE="$(sw_format_number "${MOON_DISTANCE_KM}")"
    MOON_ALTITUDE="${MOON_ALTITUDE%.*}"
    MOON_AZIMUTH="${MOON_AZIMUTH%.*}"

}

moon_analyze_events() {

    local file

    file="$(sw_cache_file "${MOON_EVENTS_CACHE}")"

    if [[ "$(jq '.data.table.rows[0].cells | length' "${file}")" -eq 0 ]]; then
        MOON_EVENT_TYPE=""
        MOON_EVENT_DATE=""
        MOON_RISE=""
        MOON_SET=""
        MOON_OBSCURATION=""
        return 0
    fi

    IFS='|' read -r \
        MOON_EVENT_TYPE \
        MOON_EVENT_DATE \
        MOON_RISE \
        MOON_SET \
        MOON_OBSCURATION \
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

moon_update_status() {

    local timestamp1=""
    local timestamp2=""

    MOON_SUPER=""

    MOON_STATUS="${SW_STATUS_OK}"
    
    if (( MOON_DISTANCE_KM <= 360000 )) && [[ "$MOON_PHASE" == "Full Moon" ]]; then
        MOON_SUPER="$(sw_translate "Supermoon")"
        MOON_STATUS="${SW_STATUS_INFO}"
    fi

    if [[ -n "${MOON_EVENT_DATE}" ]]; then
        timestamp1="$(date -d "${MOON_EVENT_DATE}" +%F)"
        timestamp2="$(date +%F)"

        if [[ "${timestamp1}" == "${timestamp2}" ]]; then
            MOON_STATUS="${SW_STATUS_CRITICAL}"
        fi
    fi
    
    
}

moon_analyze() {

    moon_analyze_position || return 1

    moon_analyze_events || return 1

    moon_update_status

}

moon_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.icon" "lucide/moon"
    sw_state_set "module.label" "$(sw_translate "Moon")"
    sw_state_set "module.order" "$MODULE_ORDER"

    sw_state_set "phase" "$(moon_phase_name "${MOON_PHASE}")"
    sw_state_set "phase.label" "$(sw_translate "Phase")"
    sw_state_set "phase.order" "10"

    echo "${MOON_PHASE}" >> ~/scripts/syswatch/fases.txt
    
    if [[ -n "${MOON_SUPER}" ]]; then
        sw_state_set "size" "${MOON_SUPER}"
        sw_state_set "size.label" "$(sw_translate "Size")"
        sw_state_set "size.order" "15"
        sw_state_set "size.hidden" "false"
    else
        sw_state_set "size" "Normal"
        sw_state_set "size.label" "$(sw_translate "Size")"
        sw_state_set "size.order" "15"
        sw_state_set "size.hidden" "true"
    fi    
    
    sw_state_set "constellation" "$(sw_zodiac_emoji ${MOON_CONSTELLATION}) $MOON_CONSTELLATION"
    sw_state_set "constellation.label" "$(sw_translate "Constellation")"
    sw_state_set "constellation.order" "20"

    sw_state_set "distance" "${MOON_DISTANCE}"
    sw_state_set "distance.label" "$(sw_translate "Distance")"
    sw_state_set "distance.unit" "km"
    sw_state_set "distance.order" "30"

    sw_state_set "altitude" "${MOON_ALTITUDE}"
    sw_state_set "altitude.label" "$(sw_translate "Altitude")"
    sw_state_set "altitude.unit" "°"
    sw_state_set "altitude.order" "40"
    sw_state_set "altitude.hidden" "true"

    sw_state_set "azimuth" "${MOON_AZIMUTH}"
    sw_state_set "azimuth.label" "$(sw_translate "Azimuth")"
    sw_state_set "azimuth.unit" "°"
    sw_state_set "azimuth.order" "50"
    sw_state_set "azimuth.hidden" "true"

    if [[ -n "${MOON_EVENT_TYPE}" ]]; then
        sw_state_set "next_event" "$(moon_event_name "${MOON_EVENT_TYPE}")"
        sw_state_set "next_event.label" "$(sw_translate "Next event")"
        sw_state_set "next_event.order" "60"
        sw_state_set "next_event_date" "$(moon_format_date "${MOON_EVENT_DATE}")"
        sw_state_set "next_event_date.label" "$(sw_translate "Date")"
        sw_state_set "next_event_date.order" "70"
        sw_state_set "next_event.hidden" "false"
        sw_state_set "next_event_date.hidden" "false"
    else
        sw_state_set "next_event.hidden" "true"
        sw_state_set "next_event_date.hidden" "true"
    fi
    
    sw_state_set "image" "$(moon_phase_image "${MOON_PHASE}")"

    sw_state_set "image.label" " "
    sw_state_set "image.widget" "image"
    sw_state_set "image.unit" ""
    sw_state_set "image.order" "80"
    sw_state_set "image.warning" "${MOON_WARNING}"
    sw_state_set "image.critical" "${MOON_CRITICAL}"

    sw_state_set "moonrise" "${MOON_RISE}"
    sw_state_set "moonrise.hidden" "true"
    sw_state_set "moonset" "${MOON_SET}"
    sw_state_set "moonset.hidden" "true"

    sw_state_set "right_ascension" "${MOON_RA}"
    sw_state_set "right_ascension.hidden" "true"

    sw_state_set "declination" "${MOON_DEC}"
    sw_state_set "declination.hidden" "true"

    sw_state_set "magnitude" "${MOON_MAGNITUDE}"
    sw_state_set "magnitude.hidden" "true"

    sw_state_set "elongation" "${MOON_ELONGATION}"
    sw_state_set "elongation.hidden" "true"

    sw_state_set "obscuration" "${MOON_OBSCURATION}"
    sw_state_set "obscuration.hidden" "true"

}



moon_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Moon value: ${MOON_PHASE} (${MOON_STATUS})"

}

sw_module_run() {

    local module

    module="moon"

    sw_module_load_config "astronomy"

    sw_state_use "${module}"
    sw_state_load

    moon_fetch

    moon_analyze

    sw_status_update "${MOON_STATUS}" || return 1

    moon_update_state

    sw_state_save

    moon_report

}
