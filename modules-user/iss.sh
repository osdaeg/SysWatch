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

readonly MODULE_NAME="ISS"
readonly MODULE_DESCRIPTION="Monitorize ISS passing over a place"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-800}
MODULE_REMOTE=${MODULE_REMOTE:-""}


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly ISS_WARNING_MINUTES="${ISS_WARNING_MINUTES:-60}"
readonly ISS_CRITICAL_MINUTES="${ISS_CRITICAL_MINUTES:-5}"
readonly ISS_CACHE_HOURS="${ISS_CACHE_HOURS:-2}"

# Independent from WEATHER_LAT/WEATHER_LON on purpose -- falls back to
# them only for convenience (same location, no need to duplicate config),
# but if weather.sh's coordinates ever change for its own reasons, this
# module isn't dragged along with it.
readonly ISS_LAT="${ISS_LAT:-${WEATHER_LAT:-}}"
readonly ISS_LON="${ISS_LON:-${WEATHER_LON:-}}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

ISS_STATUS="${SW_STATUS_UNKNOWN}"

ISS_NEXT_PASS=""
ISS_NEXT_PASS_LOCAL=""
ISS_VISIBLE_START=""
ISS_VISIBLE_END=""

ISS_START_EPOCH=0
ISS_END_EPOCH=0

ISS_MINUTES_REMAINING=0

ISS_DURATION=0
ISS_ELEVATION=0
ISS_DIRECTION=""

ISS_VISIBLE=false

ISS_REMAINING_TEXT=""


# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Cache
# -----------------------------------------------------------------------------

iss_refresh_cache() {

    local response

    if ! sw_cache_is_expired \
        "iss.json" \
        "$(( ISS_CACHE_HOURS * 3600 ))"; then

        return 0

    fi

    sw_log_debug \
        "${MODULE_NAME}" \
        "Refreshing ISS cache"

    response="$(
        curl \
            --silent \
            --show-error \
            --fail \
            --connect-timeout 10 \
            --max-time 30 \
            "https://iss-api.polluxlabs.io/iss-pass?lat=${ISS_LAT}&lon=${ISS_LON}&visible_only=true"
    )"

    echo "$response" > iss.json

    if [[ -z "${response}" ]]; then
        if sw_cache_exists "iss.json"; then

            sw_log_warning \
                "${MODULE_NAME}" \
                "Unable to refresh ISS cache. Using cached data."

                return 0

        fi

        sw_log_warning \
            "${MODULE_NAME}" \
            "Unable to refresh ISS cache"

        return 1
        

    fi

    if ! jq empty >/dev/null 2>&1 <<< "${response}"; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "Invalid JSON response from ISS API"

        return 1

    fi

    if ! jq -e '.passes | length > 0' >/dev/null 2>&1 <<< "${response}"; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "No ISS passes returned by API"

        return 1

    fi

    sw_cache_write "iss.json" <<< "${response}"

    sw_log_debug \
        "${MODULE_NAME}" \
        "ISS cache updated"

}

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

iss_format_remaining() {

    local minutes="$1"
    local visible="$2"

    if [[ "${visible}" == "true" ]]; then
        echo "Visible now"
        return
    fi

    if (( minutes <= 0 )); then
        echo "Now"
        return
    fi

    if (( minutes < 60 )); then
        echo "${minutes} min"
        return
    fi

    local hours=$(( minutes / 60 ))
    local mins=$(( minutes % 60 ))

    if (( mins == 0 )); then
        echo "${hours} h"
    else
        printf "%d h %02d min\n" "${hours}" "${mins}"
    fi

}

iss_update_dates() {

    if ! ISS_START_EPOCH="$(date -d "${ISS_VISIBLE_START}" +%s 2>/dev/null)" ||
       ! ISS_END_EPOCH="$(date -d "${ISS_VISIBLE_END}" +%s 2>/dev/null)"
    then

        sw_log_warning \
            "${MODULE_NAME}" \
            "Could not parse pass dates from API response (start='${ISS_VISIBLE_START}', end='${ISS_VISIBLE_END}')"

        return 1

    fi

    ISS_NEXT_PASS_LOCAL="$(
        date \
            -d "@${ISS_START_EPOCH}" \
            '+%Y-%m-%d %H:%M'
    )"

}

# -----------------------------------------------------------------------------
# JSON
# -----------------------------------------------------------------------------

iss_load_data() {

    read \
        ISS_NEXT_PASS \
        ISS_VISIBLE_START \
        ISS_VISIBLE_END \
        ISS_DURATION \
        ISS_ELEVATION \
        ISS_DIRECTION \
    < <(

        jq -r '
            .passes[0] |
            [
                .rise.time,
                .visible_start,
                .visible_end,
                .visible_duration_sec,
                .culmination.elevation_deg,
                .rise.compass
            ] | @tsv
        ' < "$(sw_cache_file "iss.json")"
    )

}

iss_collect() {

    local now_epoch

    if ! iss_refresh_cache && ! sw_cache_exists "iss.json"; then

        ISS_STATUS="${SW_STATUS_UNKNOWN}"
        return 1

    fi

    iss_load_data

    [[ -n "${ISS_VISIBLE_START}" ]] || {

        sw_log_warning \
            "${MODULE_NAME}" \
            "No ISS passes returned"

        ISS_STATUS="${SW_STATUS_UNKNOWN}"

        return 1

        }

    now_epoch="$(date +%s)"

    iss_update_dates || return 1

    ISS_MINUTES_REMAINING=$(( (ISS_START_EPOCH - now_epoch) / 60 ))

    if (( now_epoch >= ISS_START_EPOCH &&
          now_epoch <= ISS_END_EPOCH )); then

        ISS_VISIBLE=true

    else

        ISS_VISIBLE=false

    fi

    ISS_REMAINING_TEXT="$(
        iss_format_remaining \
            "${ISS_MINUTES_REMAINING}" \
            "${ISS_VISIBLE}"
        )"

    
}

iss_analyze() {

    ISS_STATUS="${SW_STATUS_OK}"

    if [[ "${ISS_VISIBLE}" == "true" ]]; then

        ISS_STATUS="${SW_STATUS_CRITICAL}"

    elif (( ISS_MINUTES_REMAINING <= ISS_CRITICAL_MINUTES )); then

        ISS_STATUS="${SW_STATUS_CRITICAL}"

    elif (( ISS_MINUTES_REMAINING <= ISS_WARNING_MINUTES )); then

        ISS_STATUS="${SW_STATUS_WARNING}"

    fi

}

iss_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "ISS"
    sw_state_set "module.icon" "lucide/satellite"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Data
    # -------------------------------------------------------------------------

    sw_state_set "minutes_remaining" "${ISS_MINUTES_REMAINING}"
    sw_state_set "next_pass" "${ISS_NEXT_PASS}"
    sw_state_set "next_pass_local" "${ISS_NEXT_PASS_LOCAL}"
    sw_state_set "duration" "${ISS_DURATION}"
    sw_state_set "elevation" "${ISS_ELEVATION}"
    sw_state_set "direction" "${ISS_DIRECTION}"

    sw_state_set "minutes_remaining.label" "Remaining"
    sw_state_set "minutes_remaining.display" "${ISS_REMAINING_TEXT}"
    sw_state_set "minutes_remaining.widget" "line"
    sw_state_set "minutes_remaining.unit" "min"
    sw_state_set "minutes_remaining.order" "10"
    sw_state_set "minutes_remaining.warning" "${ISS_WARNING_MINUTES}"
    sw_state_set "minutes_remaining.critical" "${ISS_CRITICAL_MINUTES}"
    #sw_state_set "minutes_remaining.hidden" "true"

    sw_state_set "next_pass_local.label" "Next pass"
    sw_state_set "next_pass_local.widget" "text"
    sw_state_set "next_pass_local.order" "20"
    sw_state_set "next_pass.hidden" "true"

    sw_state_set "duration.label" "Duration"
    sw_state_set "duration.widget" "text"
    sw_state_set "duration.unit" "s"
    sw_state_set "duration.order" "30"

    sw_state_set "elevation.label" "Elevation"
    sw_state_set "elevation.widget" "text"
    sw_state_set "elevation.unit" "°"
    sw_state_set "elevation.order" "40"

    sw_state_set "direction.label" "Direction"
    sw_state_set "direction.widget" "text"
    sw_state_set "direction.order" "50"

}

iss_report() {

    if [[ "${ISS_VISIBLE}" == "true" ]]; then

        sw_log_info \
            "${MODULE_NAME}" \
            "ISS visible now (${ISS_DURATION}s, ${ISS_ELEVATION}°)"

    else

        sw_log_info \
            "${MODULE_NAME}" \
            "Next ISS pass in ${ISS_REMAINING_TEXT} (${ISS_STATUS})"

    fi

}

sw_module_run() {

    sw_state_use "iss"
    sw_state_load

    iss_collect || return 1

    iss_analyze

    sw_status_update "${ISS_STATUS}" || return 1

    iss_update_state

    sw_state_save

    iss_report

    # Optional history
    sw_csv_append \
        "iss" \
        "minutes_remaining" \
        "${ISS_MINUTES_REMAINING}"

}



