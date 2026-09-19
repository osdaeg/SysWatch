#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# SMN (Servicio Meteorológico Nacional) current conditions module
#
# Does not poll the API itself -- Daniel's own poller script (systemd
# user service + uvicorn) already fetches this every 30 minutes and
# writes it to cache/actual.json. This module only reads that file, same
# pattern as rkhunter.sh/chkrootkit.sh/clamav.sh reading someone else's
# log.
#
# Coexists with weather.sh (OpenWeatherMap) on purpose -- two independent
# sources, not a replacement.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="SmnWeather"
readonly MODULE_DESCRIPTION="SMN current weather conditions (unofficial API)"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-8}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly SMN_ACTUAL_FILE="${SMN_ACTUAL_FILE:-${CACHE_DIR}/actual.json}"

# Daniel's poller runs every 30 min -- if the cache is much older than
# that, the poller itself may have died.
readonly SMN_MAX_AGE_MINUTES="${SMN_MAX_AGE_MINUTES:-90}"

readonly SMN_TEMP_WARNING_HIGH="${SMN_TEMP_WARNING_HIGH:-30}"
readonly SMN_TEMP_CRITICAL_HIGH="${SMN_TEMP_CRITICAL_HIGH:-35}"
readonly SMN_TEMP_WARNING_LOW="${SMN_TEMP_WARNING_LOW:-5}"
readonly SMN_TEMP_CRITICAL_LOW="${SMN_TEMP_CRITICAL_LOW:-0}"

# Asumiendo km/h (unidad típica de los boletines del SMN) -- confirmame
# si tu actual.json en realidad viene en otra unidad.
readonly SMN_WIND_WARNING_KMH="${SMN_WIND_WARNING_KMH:-40}"
readonly SMN_WIND_CRITICAL_KMH="${SMN_WIND_CRITICAL_KMH:-60}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

SMN_TEMP=""
SMN_FEELS_LIKE=""
SMN_HUMIDITY=""
SMN_PRESSURE=""
SMN_VISIBILITY=""
SMN_WIND_DIR=""
SMN_WIND_SPEED=""
SMN_WEATHER_ID=""
SMN_WEATHER_DESC=""
SMN_DEPARTMENT=""
SMN_DATE=""
SMN_IS_DAY="true"
SMN_STATUS="${SW_STATUS_OK}"
SMN_REASON=""

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

smn_weather_icon() {

    local code="$1"
    local is_day="$2"

    case "${code}" in

        3)
            [[ "${is_day}" == "true" ]] && printf 'lucide/sun\n' || printf 'lucide/moon\n'
            ;;

        13|19|25)
            [[ "${is_day}" == "true" ]] && printf 'lucide/cloud-sun\n' || printf 'lucide/cloud-moon\n'
            ;;

        37|43)
            printf 'lucide/cloudy\n'
            ;;

        61|67)
            printf 'lucide/cloud-fog\n'
            ;;

        71)
            printf 'lucide/cloud-drizzle\n'
            ;;

        72|73)
            printf 'lucide/cloud-rain\n'
            ;;

        76|81|89)
            printf 'lucide/cloud-lightning\n'
            ;;

        77)
            printf 'lucide/cloud-hail\n'
            ;;

        78|79|85|96)
            printf 'lucide/cloud-snow\n'
            ;;

        *)
            printf 'lucide/cloud\n'
            ;;

    esac

}

smn_weather_collect() {

    sw_require_command jq || return 127

    if [[ ! -r "${SMN_ACTUAL_FILE}" ]]; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "Cannot read ${SMN_ACTUAL_FILE} (missing, or the poller hasn't run yet)"

        return 1

    fi

    local mtime
    mtime="$(stat -c %Y "${SMN_ACTUAL_FILE}" 2>/dev/null)"

    local age_minutes
    age_minutes=$(( ( $(date +%s) - mtime ) / 60 ))

    if (( age_minutes > SMN_MAX_AGE_MINUTES )); then

        sw_log_warning \
            "${MODULE_NAME}" \
            "${SMN_ACTUAL_FILE} is ${age_minutes}m old (expected refresh every ~30m) -- poller may be down"

        return 1

    fi

    local json
    json="$(cat "${SMN_ACTUAL_FILE}" 2>/dev/null)"

    if [[ -z "${json}" ]] || ! jq empty >/dev/null 2>&1 <<< "${json}"; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "${SMN_ACTUAL_FILE} is empty or not valid JSON"

        return 1

    fi

    SMN_DATE="$(jq -r '.date // ""' <<< "${json}")"
    SMN_TEMP="$(jq -r '.temperature // empty' <<< "${json}")"
    SMN_FEELS_LIKE="$(jq -r '.feels_like // empty' <<< "${json}")"
    SMN_HUMIDITY="$(jq -r '.humidity // empty' <<< "${json}")"
    SMN_PRESSURE="$(jq -r '.pressure // empty' <<< "${json}")"
    SMN_VISIBILITY="$(jq -r '.visibility // empty' <<< "${json}")"
    SMN_WIND_DIR="$(jq -r '.wind.direction // "N/A"' <<< "${json}")"
    SMN_WIND_SPEED="$(jq -r '.wind.speed // empty' <<< "${json}")"
    SMN_WEATHER_ID="$(jq -r '.weather.id // 0' <<< "${json}")"
    SMN_WEATHER_DESC="$(jq -r '.weather.description // "N/A"' <<< "${json}")"
    SMN_DEPARTMENT="$(jq -r '.location.department // .location.name // "N/A"' <<< "${json}")"

    if [[ -z "${SMN_TEMP}" ]]; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "No temperature in ${SMN_ACTUAL_FILE}"

        return 1

    fi

    local hour
    hour="$(date -d "${SMN_DATE}" '+%H' 2>/dev/null)"

    if [[ -n "${hour}" ]] && (( 10#${hour} >= 7 && 10#${hour} < 20 )); then

        SMN_IS_DAY="true"

    else

        SMN_IS_DAY="false"

    fi

}

smn_weather_analyze() {

    SMN_STATUS="${SW_STATUS_OK}"
    SMN_REASON=""

    local temp_int="${SMN_TEMP%%.*}"

    if (( temp_int >= SMN_TEMP_CRITICAL_HIGH )); then

        SMN_STATUS="${SW_STATUS_CRITICAL}"
        SMN_REASON="Temperatura muy alta (${SMN_TEMP}°C)"

    elif (( temp_int <= SMN_TEMP_CRITICAL_LOW )); then

        SMN_STATUS="${SW_STATUS_CRITICAL}"
        SMN_REASON="Temperatura muy baja (${SMN_TEMP}°C)"

    elif [[ -n "${SMN_WIND_SPEED}" ]] && (( ${SMN_WIND_SPEED%%.*} >= SMN_WIND_CRITICAL_KMH )); then

        SMN_STATUS="${SW_STATUS_CRITICAL}"
        SMN_REASON="Viento muy fuerte (${SMN_WIND_SPEED} km/h)"

    elif (( temp_int >= SMN_TEMP_WARNING_HIGH )); then

        SMN_STATUS="${SW_STATUS_WARNING}"
        SMN_REASON="Temperatura alta (${SMN_TEMP}°C)"

    elif (( temp_int <= SMN_TEMP_WARNING_LOW )); then

        SMN_STATUS="${SW_STATUS_WARNING}"
        SMN_REASON="Temperatura baja (${SMN_TEMP}°C)"

    elif [[ -n "${SMN_WIND_SPEED}" ]] && (( ${SMN_WIND_SPEED%%.*} >= SMN_WIND_WARNING_KMH )); then

        SMN_STATUS="${SW_STATUS_WARNING}"
        SMN_REASON="Viento fuerte (${SMN_WIND_SPEED} km/h)"

    fi

}

smn_weather_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.label" "Clima SMN"
    sw_state_set "module.icon" "$(smn_weather_icon "${SMN_WEATHER_ID}" "${SMN_IS_DAY}")"
    sw_state_set "module.order" "$MODULE_ORDER"

    sw_state_set "location" "${SMN_DEPARTMENT}"
    sw_state_set "location.label" "Ubicación"
    sw_state_set "location.order" "5"

    sw_state_set "temp" "${SMN_TEMP}"
    sw_state_set "temp.label" "Temperatura"
    sw_state_set "temp.unit" "°C"
    sw_state_set "temp.order" "10"

    sw_state_set "feels_like" "${SMN_FEELS_LIKE}"
    sw_state_set "feels_like.label" "Sensación térmica"
    sw_state_set "feels_like.unit" "°C"
    sw_state_set "feels_like.order" "20"
    if [[ -z "${SMN_FEELS_LIKE}" ]]; then
        sw_state_set "feels_like.hidden" "true"
    else
        sw_state_set "feels_like.hidden" "false"
    fi

    sw_state_set "humidity" "${SMN_HUMIDITY}"
    sw_state_set "humidity.label" "Humedad"
    sw_state_set "humidity.unit" "%"
    sw_state_set "humidity.order" "30"

    sw_state_set "condition" "${SMN_WEATHER_DESC}"
    sw_state_set "condition.label" "Condición"
    sw_state_set "condition.order" "40"

    sw_state_set "wind" "${SMN_WIND_DIR}$([[ -n "${SMN_WIND_SPEED}" ]] && printf ' %s km/h' "${SMN_WIND_SPEED}")"
    sw_state_set "wind.label" "Viento"
    sw_state_set "wind.order" "50"

    sw_state_set "pressure" "${SMN_PRESSURE}"
    sw_state_set "pressure.label" "Presión"
    sw_state_set "pressure.unit" "hPa"
    sw_state_set "pressure.order" "60"

    sw_state_set "visibility" "${SMN_VISIBILITY}"
    sw_state_set "visibility.label" "Visibilidad"
    sw_state_set "visibility.unit" "km"
    sw_state_set "visibility.order" "70"

    sw_state_set "reason" "${SMN_REASON}"
    sw_state_set "reason.label" "Detalle"
    sw_state_set "reason.order" "80"
    if [[ "${SMN_STATUS}" == "${SW_STATUS_OK}" ]]; then
        sw_state_set "reason.hidden" "true"
    else
        sw_state_set "reason.hidden" "false"
    fi

    echo "Condición: ${SMN_WEATHER_DESC} - Detalle: ${SMN_REASON}" >> ~/scripts/syswatch/smn_condicion.txt

}

smn_weather_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "SMN (${SMN_DEPARTMENT}): ${SMN_TEMP}°C, ${SMN_WEATHER_DESC} (${SMN_STATUS})"

}

sw_module_run() {

    sw_state_use "smn_weather"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi
    
    sw_state_load

    smn_weather_collect || return 1

    smn_weather_analyze

    sw_status_update "${SMN_STATUS}" || return 1

    smn_weather_update_state

    sw_state_save

    smn_weather_report

}
