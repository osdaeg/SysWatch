#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Weather monitoring module (OpenWeatherMap Current Weather API, free tier)
#
# First module in SysWatch that calls an external internet service rather
# than reading local system data -- treated accordingly: network failures
# (API down, rate limited, bad key) log a warning and skip this cycle
# WITHOUT touching the previous status, rather than being reported as
# CRITICAL. A failed weather check is not the same thing as bad weather.
#
# No sustained-threshold debounce here on purpose (unlike cpu.sh/disk.sh/
# temperature.sh): a weather reading already reflects a real current
# condition, not sensor noise, so there's nothing to filter out.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Weather"
readonly MODULE_DESCRIPTION="Weather monitoring (OpenWeatherMap)"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-540}
MODULE_ORDER=${MODULE_ORDER:-9}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

WEATHER_LAT1="${WEATHER_LAT:-}"
WEATHER_LON1="${WEATHER_LON:-}"
readonly WEATHER_API_KEY="${WEATHER_API_KEY:-}"
readonly WEATHER_LANG="${WEATHER_LANG:-en}"

readonly WEATHER_TIMEOUT_SECONDS="${WEATHER_TIMEOUT_SECONDS:-10}"

readonly WEATHER_TEMP_WARNING_HIGH="${WEATHER_TEMP_WARNING_HIGH:-30}"
readonly WEATHER_TEMP_CRITICAL_HIGH="${WEATHER_TEMP_CRITICAL_HIGH:-35}"
readonly WEATHER_TEMP_WARNING_LOW="${WEATHER_TEMP_WARNING_LOW:-5}"
readonly WEATHER_TEMP_CRITICAL_LOW="${WEATHER_TEMP_CRITICAL_LOW:-0}"

readonly WEATHER_WIND_WARNING_KMH="${WEATHER_WIND_WARNING_KMH:-40}"
readonly WEATHER_WIND_CRITICAL_KMH="${WEATHER_WIND_CRITICAL_KMH:-60}"

readonly WEATHER_RAIN_WARNING_MMH="${WEATHER_RAIN_WARNING_MMH:-10}"
readonly WEATHER_RAIN_CRITICAL_MMH="${WEATHER_RAIN_CRITICAL_MMH:-30}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

WEATHER_TEMP=0
WEATHER_FEELS_LIKE=0
WEATHER_HUMIDITY=0
WEATHER_WIND_KMH=0
WEATHER_RAIN_MMH=0
WEATHER_SNOW_MMH=0
WEATHER_MAIN="Unknown"
WEATHER_DESCRIPTION=""
WEATHER_CITY=""
WEATHER_DT=0
WEATHER_SUNRISE=0
WEATHER_SUNSET=0
WEATHER_IS_DAY="true"
WEATHER_STATUS="${SW_STATUS_OK}"
WEATHER_REASON=""
WEATHER_ID=0
WEATHER_SPECIAL_ICON=""

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

latlong() {

    # Generar latitud y longitud aleatorias entre -90 y 90
    WEATHER_LAT1=$((RANDOM % 181 - 90))
    WEATHER_LON1=$((RANDOM % 361 - 180))

    MODULE_INTERVAL=30

}

weather_collect() {

    sw_require_command curl || return 127
    sw_require_command jq || return 127

    #latlong

    if [[ -z "${WEATHER_LAT1}" || -z "${WEATHER_LON1}" || -z "${WEATHER_API_KEY}" ]]; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "WEATHER_LAT1/WEATHER_LON1/WEATHER_API_KEY are not fully set"

        return 1

    fi

    local response

    response="$(
        curl \
            --silent \
            --show-error \
            --max-time "${WEATHER_TIMEOUT_SECONDS}" \
            "https://api.openweathermap.org/data/2.5/weather?lat=${WEATHER_LAT1}&lon=${WEATHER_LON1}&units=metric&lang=${WEATHER_LANG}&appid=${WEATHER_API_KEY}" \
            2>/dev/null
    )"

    echo "${response}" >"${PROJECT_DIR}/cache/weather.json"

    if [[ -z "${response}" ]]; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "No response from OpenWeatherMap (network issue or timeout)"

        return 1

    fi

    local cod
    cod="$(jq -r '.cod // "?"' <<<"${response}")"

    if [[ "${cod}" != "200" ]]; then

        local message
        message="$(jq -r '.message // "unknown error"' <<<"${response}")"

        sw_log_warning \
            "${MODULE_NAME}" \
            "OpenWeatherMap returned an error (cod=${cod}): ${message}"

        return 1

    fi

    WEATHER_TEMP="$(jq -r '.main.temp' <<<"${response}")"
    WEATHER_FEELS_LIKE="$(jq -r '.main.feels_like' <<<"${response}")"
    WEATHER_HUMIDITY="$(jq -r '.main.humidity' <<<"${response}")"

    local wind_ms
    wind_ms="$(jq -r '.wind.speed // 0' <<<"${response}")"
    WEATHER_WIND_KMH="$(awk -v v="${wind_ms}" 'BEGIN { printf "%.1f", v * 3.6 }')"

    WEATHER_RAIN_MMH="$(jq -r '.rain["1h"] // 0' <<<"${response}")"
    WEATHER_SNOW_MMH="$(jq -r '.snow["1h"] // 0' <<<"${response}")"

    WEATHER_MAIN="$(jq -r '.weather[0].main // "Unknown"' <<<"${response}")"
    WEATHER_DESCRIPTION="$(jq -r '.weather[0].description // ""' <<<"${response}")"
    WEATHER_ID="$(jq -r '.weather[0].id // ""' <<<"${response}")"
    WEATHER_CITY="$(jq -r '.name // ""' <<<"${response}")"
    WEATHER_COUNTRY="$(jq -r '.sys.country // ""' <<<"${response}")"

    # dt/sunrise/sunset all come as UTC unix timestamps from the API
    # itself, so comparing them directly avoids any local-timezone
    # confusion on the server.
    WEATHER_DT="$(jq -r '.dt // 0' <<<"${response}")"
    WEATHER_SUNRISE="$(jq -r '.sys.sunrise // 0' <<<"${response}")"
    WEATHER_SUNSET="$(jq -r '.sys.sunset // 0' <<<"${response}")"

    if ((WEATHER_SUNRISE > 0 && WEATHER_SUNSET > 0 && \
        WEATHER_DT >= WEATHER_SUNRISE && WEATHER_DT < WEATHER_SUNSET)); then

        WEATHER_IS_DAY="true"

    else

        WEATHER_IS_DAY="false"

    fi

}

weather_analyze() {

    WEATHER_STATUS="${SW_STATUS_OK}"
    WEATHER_REASON=""

    local temp_int="${WEATHER_TEMP%%.*}"
    local wind_int="${WEATHER_WIND_KMH%%.*}"
    local rain_int="${WEATHER_RAIN_MMH%%.*}"

    # Worst-first: once CRITICAL is set, nothing below should downgrade it.

    if [[ "${WEATHER_MAIN}" == "Tornado" ]]; then

        WEATHER_STATUS="${SW_STATUS_CRITICAL}"
        WEATHER_REASON="$(sw_translate "Tornado")"
        WEATHER_SPECIAL_ICON="lucide/tornado"

    elif ((temp_int >= WEATHER_TEMP_CRITICAL_HIGH)); then

        WEATHER_STATUS="${SW_STATUS_CRITICAL}"
        WEATHER_REASON="$(printf "$(sw_translate "Very high temperature (%s°C)")\n" \
            "${WEATHER_TEMP}")"
        WEATHER_SPECIAL_ICON="lucide/thermometer-sun"

    elif ((temp_int <= WEATHER_TEMP_CRITICAL_LOW)); then

        WEATHER_STATUS="${SW_STATUS_CRITICAL}"
        WEATHER_REASON="$(printf "$(sw_translate "Very low temperature (%s°C)")\n" \
            "${WEATHER_TEMP}")"
        WEATHER_SPECIAL_ICON="lucide/thermometer-snowflake"

    elif ((wind_int >= WEATHER_WIND_CRITICAL_KMH)); then

        WEATHER_STATUS="${SW_STATUS_CRITICAL}"
        WEATHER_REASON="$(printf "$(sw_translate "Very strong wind (%s km/h)")\n" \
            "${WEATHER_WIND_KMH}")"
        WEATHER_SPECIAL_ICON="lucide/thermometer-wind"

    elif ((rain_int >= WEATHER_RAIN_CRITICAL_MMH)); then

        WEATHER_STATUS="${SW_STATUS_CRITICAL}"
        WEATHER_REASON="$(printf "$(sw_translate "Heavy rain (%s mm/h)")\n" \
            "${WEATHER_RAIN_MMH}")"
        WEATHER_SPECIAL_ICON="lucide/cloud-rain-wind"

    elif ((temp_int >= WEATHER_TEMP_WARNING_HIGH)); then

        WEATHER_STATUS="${SW_STATUS_WARNING}"
        WEATHER_REASON="$(printf "$(sw_translate "High temperature (%s°C)")\n" \
            "${WEATHER_TEMP}")"
        WEATHER_SPECIAL_ICON="lucide/thermometer-sun"

    elif ((temp_int <= WEATHER_TEMP_WARNING_LOW)); then

        WEATHER_STATUS="${SW_STATUS_WARNING}"
        WEATHER_REASON="$(printf "$(sw_translate "Low temperature (%s°C)")\n" \
            "${WEATHER_TEMP}")"
        WEATHER_SPECIAL_ICON="lucide/thermometer-snowflake"

    elif ((wind_int >= WEATHER_WIND_WARNING_KMH)); then

        WEATHER_STATUS="${SW_STATUS_WARNING}"
        WEATHER_REASON="$(printf "$(sw_translate "Strong wind (%s km/h)")\n" \
            "${WEATHER_WIND_KMH}")"
        WEATHER_SPECIAL_ICON="lucide/thermometer-wind"

    elif ((rain_int >= WEATHER_RAIN_WARNING_MMH)); then

        WEATHER_STATUS="${SW_STATUS_WARNING}"
        WEATHER_REASON="$(printf "$(sw_translate "Rain (%s mm/h)")\n" \
            "${WEATHER_RAIN_MMH}")"
        WEATHER_SPECIAL_ICON="lucide/cloud-rain-wind"

    elif [[ "${WEATHER_MAIN}" == "Thunderstorm" ]]; then

        WEATHER_STATUS="${SW_STATUS_WARNING}"
        WEATHER_REASON="$(sw_translate "Thunderstorm")"
        WEATHER_SPECIAL_ICON="lucide/cloud-lightning"

    fi

}

pick_icon() {
    local day_icon="$1"
    local night_icon="$2"
    if [[ "${WEATHER_IS_DAY}" == "true" ]]; then
        sw_state_set "module.icon" "${day_icon}"
    else
        sw_state_set "module.icon" "${night_icon}"
    fi
}

weather_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.label" "$(sw_translate "Weather")"

    if [[ "${WEATHER_IS_DAY}" == "true" ]]; then

        sw_state_set "module.icon" "lucide/sun"

    else

        sw_state_set "module.icon" "lucide/moon"

    fi

    # Overrides the sun/moon default above for specific conditions.
    # Extend this as you spot icon/description mismatches.
    local condicion="${WEATHER_DESCRIPTION}"
    local id="${WEATHER_ID}"

    case "${WEATHER_ID}" in

    # Thunderstorm
    2??)
        sw_state_set "module.icon" "lucide/cloud-lightning"
        ;;

    # Drizzle
    3??)
        sw_state_set "module.icon" "lucide/cloud-drizzle"
        ;;

    # Rain
    511)
        sw_state_set "module.icon" "lucide/snowflake"
        ;;

    5??)
        sw_state_set "module.icon" "lucide/cloud-rain"
        ;;

    # Snow
    6??)
        sw_state_set "module.icon" "lucide/cloud-snow"
        ;;

    # Atmosphere
    7??)
        sw_state_set "module.icon" "lucide/fog"
        ;;

    # Clear
    800)
        if [[ "${WEATHER_IS_DAY}" == "true" ]]; then
            sw_state_set "module.icon" "lucide/sun"
        else
            sw_state_set "module.icon" "lucide/moon"
        fi
        ;;

    # Few / scattered clouds
    801 | 802)
        if [[ "${WEATHER_IS_DAY}" == "true" ]]; then
            sw_state_set "module.icon" "lucide/cloud-sun"
        else
            sw_state_set "module.icon" "lucide/cloud-moon"
        fi
        ;;

    # Broken / overcast clouds
    803 | 804)
        sw_state_set "module.icon" "lucide/cloudy"
        ;;

    *) ;;
    esac

    if [[ -n "${WEATHER_SPECIAL_ICON}" ]]; then
        sw_state_set "module.icon" "${WEATHER_SPECIAL_ICON}"
    fi

    local location="${WEATHER_CITY}"

    [[ -n "${WEATHER_COUNTRY}" ]] && location="${WEATHER_CITY}, ${WEATHER_COUNTRY}"

    if [[ -n "${WEATHER_SPECIAL_ICON}" ]]; then
        sw_state_set "location" "${location}"
    else
        sw_state_set "location" "$(sw_translate "Undefined")"
    fi

    sw_state_set "location" "${location}"
    sw_state_set "location.label" "$(sw_translate "Location")"

    sw_state_set "module.order" "$MODULE_ORDER"

    sw_state_set "is_day" "${WEATHER_IS_DAY}"
    sw_state_set "is_day.hidden" "true"

    sw_state_set "temp" "${WEATHER_TEMP}"
    sw_state_set "temp.label" "$(sw_translate "Temperature")"
    sw_state_set "temp.unit" "°C"

    sw_state_set "feels_like" "${WEATHER_FEELS_LIKE}"
    sw_state_set "feels_like.label" "$(sw_translate "Feels")"
    sw_state_set "feels_like.unit" "°C"

    sw_state_set "humidity" "${WEATHER_HUMIDITY}"
    sw_state_set "humidity.label" "$(sw_translate "Humidity")"
    sw_state_set "humidity.unit" "%"

    sw_state_set "wind" "${WEATHER_WIND_KMH}"
    sw_state_set "wind.label" "$(sw_translate "Wind")"
    sw_state_set "wind.unit" "km/h"

    sw_state_set "condition" "$(sw_translate "${condicion}")"
    sw_state_set "condition.label" "$(sw_translate "Condition")"

    sw_state_set "rain" "${WEATHER_RAIN_MMH}"
    sw_state_set "rain.label" "$(sw_translate "Rain")"
    sw_state_set "rain.unit" "mm/h"
    if [[ "${WEATHER_RAIN_MMH}" == "0" ]]; then
        sw_state_set "rain.hidden" "true"
    fi

    sw_state_set "reason" "${WEATHER_REASON}"
    sw_state_set "reason.label" "$(sw_translate "Detail")"
    if [[ "${WEATHER_STATUS}" == "${SW_STATUS_OK}" ]]; then
        sw_state_set "reason.hidden" "true"
    fi

}

weather_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Weather (${WEATHER_CITY}): ${WEATHER_TEMP}°C, viento ${WEATHER_WIND_KMH} km/h, ${WEATHER_DESCRIPTION} (${WEATHER_STATUS})"

}

sw_module_run() {

    sw_state_use "weather"
    sw_state_load

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    weather_collect || return 1

    weather_analyze

    sw_status_update "${WEATHER_STATUS}" || return 1

    weather_update_state

    sw_state_save

    weather_report

}
