#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# SMN extended forecast module
#
# Purely informational (no thresholds/alerting) -- a forecast is a
# prediction, not a current state, so it never affects this card's
# status. Reads cache/forecast.json, written by Daniel's own poller
# script every 30 minutes.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="SmnForecast"
readonly MODULE_DESCRIPTION="SMN extended forecast (unofficial API)"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-1800}
MODULE_ORDER=${MODULE_ORDER:-9}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly SMN_FORECAST_FILE="${SMN_FORECAST_FILE:-${CACHE_DIR}/forecast.json}"
readonly SMN_FORECAST_MAX_AGE_MINUTES="${SMN_FORECAST_MAX_AGE_MINUTES:-90}"
readonly SMN_FORECAST_DAYS="${SMN_FORECAST_DAYS:-5}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

SMN_FORECAST_JSON=""

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

smn_forecast_collect() {

    sw_require_command jq || return 127

    if [[ ! -r "${SMN_FORECAST_FILE}" ]]; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "Cannot read ${SMN_FORECAST_FILE} (missing, or the poller hasn't run yet)"

        return 1

    fi

    local mtime
    mtime="$(stat -c %Y "${SMN_FORECAST_FILE}" 2>/dev/null)"

    local age_minutes
    age_minutes=$((($(date +%s) - mtime) / 60))

    if ((age_minutes > SMN_FORECAST_MAX_AGE_MINUTES)); then

        sw_log_warning \
            "${MODULE_NAME}" \
            "${SMN_FORECAST_FILE} is ${age_minutes}m old -- poller may be down"

        return 1

    fi

    SMN_FORECAST_JSON="$(cat "${SMN_FORECAST_FILE}" 2>/dev/null)"

    if [[ -z "${SMN_FORECAST_JSON}" ]] || ! jq empty >/dev/null 2>&1 <<<"${SMN_FORECAST_JSON}"; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "${SMN_FORECAST_FILE} is empty or not valid JSON"

        return 1

    fi

}

smn_forecast_day_summary() {

    local idx="$1"
    local day
    day="$(jq -c ".forecast[${idx}]" <<<"${SMN_FORECAST_JSON}")"

    [[ -z "${day}" || "${day}" == "null" ]] && return 1

    local date_raw
    date_raw="$(jq -r '.date // ""' <<<"${day}")"

    local temp_max temp_min
    temp_max="$(jq -r '.temp_max // "?"' <<<"${day}")"
    temp_min="$(jq -r '.temp_min // "?"' <<<"${day}")"

    local condition
    condition="$(jq -r '.afternoon.weather.description // .morning.weather.description // "N/A"' <<<"${day}")"

    echo "Condicion: ${condition}" >>~/scripts/syswatch/smn_extendido.txt

    local rain_prob
    rain_prob="$(
        jq -r '
            [.early_morning, .morning, .afternoon, .night][]?
            | .rain_prob_range[1]? // .rain_prob_range[0]? // 0
        ' <<<"${day}" 2>/dev/null | sort -rn | head -n 1
    )"

    local date_label
    date_label="$(date -d "${date_raw}" '+%a %d/%m' 2>/dev/null)"
    [[ -z "${date_label}" ]] && date_label="${date_raw}"

    local rain_suffix=""
    [[ -n "${rain_prob}" && "${rain_prob}" != "0" ]] && rain_suffix=" (lluvia ${rain_prob}%)"

    printf '%s: %s°/%s° - %s%s\n' \
        "${date_label}" "${temp_max}" "${temp_min}" "${condition}" "${rain_suffix}"

}

smn_forecast_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_country_flags_load

    sw_state_set "module.label" "Pronóstico SMN $(sw_country_flag "AR")"
    sw_state_set "module.icon" "lucide/calendar-days"
    sw_state_set "module.order" "$MODULE_ORDER"

    local i
    local order=10
    local summary
    local count=0
    local color=true

    for ((i = 0; i < SMN_FORECAST_DAYS; i++)); do

        summary="$(smn_forecast_day_summary "${i}")"

        if [[ -z "${summary}" ]]; then

            # No data for this day this run -- if a previous run had
            # something here (e.g. the API returned fewer days this
            # time), remove it instead of leaving it stale.
            unset "SW_STATE[day${i}]"
            unset "SW_STATE[day${i}.label]"
            unset "SW_STATE[day${i}.order]"
            continue

        fi

        sw_state_set "day${i}" "${summary}"
        sw_state_set "day${i}.label" "Día $((i + 1))"
        sw_state_set "day${i}.order" "${order}"

        if [ "${color}" == "true" ]; then
            sw_state_set "day${i}.color" "pink"
            color=false
        else
            sw_state_set "day${i}.color" "white"
            color=true
        fi

        ((order += 10))
        count=$((count + 1))

    done

    # If SMN_FORECAST_DAYS itself shrank since a previous run, days
    # beyond the current range were never examined by the loop above --
    # clean those up too, same open-ended approach as smn_alerts.sh.
    while [[ -n "$(sw_state_get "day${i}")" ]]; do

        unset "SW_STATE[day${i}]"
        unset "SW_STATE[day${i}.label]"
        unset "SW_STATE[day${i}.order]"

        i=$((i + 1))

    done

    if ((count == 0)); then

        sw_state_set "detail" "Sin datos de pronóstico"
        sw_state_set "detail.label" "Estado"

    fi

}

smn_forecast_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "SMN forecast: ${SMN_FORECAST_DAYS} day(s) requested"

}

sw_module_run() {

    sw_state_use "smn_forecast"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    smn_forecast_collect || return 1

    sw_status_update "${SW_STATUS_INFO}" || return 1

    smn_forecast_update_state

    sw_state_save

    sw_timer_create "smn_forecast" "5" "statusok"

    smn_forecast_report

}
