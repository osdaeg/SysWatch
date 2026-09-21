#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# SMN official weather alerts module (CAP/RSS-derived)
#
# Reads cache/cap_alerts.json, written by Daniel's own poller script.
# That script can list the SAME event more than once (a general-feed
# bulletin and a later short-term-feed revision of it, both sharing the
# same "headline") -- this module deduplicates by headline, keeping only
# the most recently "sent" revision, and defensively re-checks "expires"
# itself rather than trusting the cache blindly.
#
# SMN's own "status" field (WARNING/CRITICAL) is used directly -- no need
# to reinvent severity thresholds, that classification is already
# authoritative.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="SmnAlerts"
readonly MODULE_DESCRIPTION="SMN official weather alerts (unofficial API)"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-1200}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly SMN_ALERTS_FILE="${SMN_ALERTS_FILE:-${CACHE_DIR}/cap_alerts.json}"
readonly SMN_ALERTS_MAX_AGE_MINUTES="${SMN_ALERTS_MAX_AGE_MINUTES:-90}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

SMN_ALERTS_JSON=""
SMN_ALERT_HEADLINES=()
SMN_ALERTS_STATUS="${SW_STATUS_OK}"

declare -A SMN_TRANSLATE=(

    ["Moderate"]="Moderado"
    ["Minor"]="Leve"
    ["Severe"]="Severo"
    ["Extreme"]="Extremo"

    ["Sun"]="Dom"
    ["Mon"]="Lun"
    ["Tue"]="Mar"
    ["Wed"]="Mié"
    ["Thu"]="Jue"
    ["Fri"]="Vie"
    ["Sat"]="Sáb"

)

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

sw_translate() {

    local text="$1"
    local english

    for english in "${!SMN_TRANSLATE[@]}"
    do

        text="${text//${english}/${SMN_TRANSLATE[$english]}}"

    done

    printf '%s\n' "${text}"

}

smn_alerts_collect() {

    sw_require_command jq || return 127

    if [[ ! -r "${SMN_ALERTS_FILE}" ]]; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "Cannot read ${SMN_ALERTS_FILE} (missing, or the poller hasn't run yet)"

        return 1

    fi

    local mtime
    mtime="$(stat -c %Y "${SMN_ALERTS_FILE}" 2>/dev/null)"

    local age_minutes
    age_minutes=$(( ( $(date +%s) - mtime ) / 60 ))

    if (( age_minutes > SMN_ALERTS_MAX_AGE_MINUTES )); then

        sw_log_warning \
            "${MODULE_NAME}" \
            "${SMN_ALERTS_FILE} is ${age_minutes}m old -- poller may be down"

        return 1

    fi

    SMN_ALERTS_JSON="$(cat "${SMN_ALERTS_FILE}" 2>/dev/null)"

    if [[ -z "${SMN_ALERTS_JSON}" ]] || ! jq empty >/dev/null 2>&1 <<< "${SMN_ALERTS_JSON}"; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "${SMN_ALERTS_FILE} is empty or not valid JSON"

        return 1

    fi

}

smn_alerts_dedupe() {

    # Reads each alert, drops anything already expired (double-checked
    # here rather than trusting the cache), and keeps only the most
    # recently "sent" entry per headline -- a later revision of the same
    # event (e.g. the short-term feed re-evaluating it) replaces an
    # earlier one instead of showing up as a separate alert.

    declare -gA SMN_BEST_SENT_EPOCH=()
    declare -gA SMN_BEST_JSON=()
    SMN_ALERT_HEADLINES=()

    local now_epoch
    now_epoch="$(date +%s)"

    local line
    local headline
    local sent_raw
    local expires_raw
    local sent_epoch
    local expires_epoch

    while IFS= read -r line; do

        [[ -z "${line}" ]] && continue

        headline="$(jq -r '.headline // "N/A"' <<< "${line}")"
        sent_raw="$(jq -r '.sent // ""' <<< "${line}")"
        expires_raw="$(jq -r '.expires // ""' <<< "${line}")"

        if ! expires_epoch="$(date -d "${expires_raw}" +%s 2>/dev/null)"; then

            sw_log_warning \
                "${MODULE_NAME}" \
                "Could not parse expires='${expires_raw}' for alert '${headline}', skipping it"

            continue

        fi

        if (( expires_epoch <= now_epoch )); then

            continue

        fi

        sent_epoch="$(date -d "${sent_raw}" +%s 2>/dev/null)"
        [[ -z "${sent_epoch}" ]] && sent_epoch=0

        if [[ -z "${SMN_BEST_SENT_EPOCH[${headline}]:-}" ]]; then

            SMN_ALERT_HEADLINES+=("${headline}")

        fi

        if [[ -z "${SMN_BEST_SENT_EPOCH[${headline}]:-}" ]] ||
           (( sent_epoch > SMN_BEST_SENT_EPOCH[${headline}] ))
        then

            SMN_BEST_SENT_EPOCH["${headline}"]="${sent_epoch}"
            SMN_BEST_JSON["${headline}"]="${line}"

        fi

    done < <(jq -c '.alerts[]?' <<< "${SMN_ALERTS_JSON}")

}

smn_alerts_analyze() {

    SMN_ALERTS_STATUS="${SW_STATUS_OK}"

    local headline
    local status

    for headline in "${SMN_ALERT_HEADLINES[@]}"; do

        status="$(jq -r '.status // "WARNING"' <<< "${SMN_BEST_JSON[${headline}]}")"

        if [[ "${status}" == "CRITICAL" ]]; then

            SMN_ALERTS_STATUS="${SW_STATUS_CRITICAL}"

        elif [[ "${status}" == "WARNING" && "${SMN_ALERTS_STATUS}" != "${SW_STATUS_CRITICAL}" ]]; then

            SMN_ALERTS_STATUS="${SW_STATUS_WARNING}"

        fi

    done

}

smn_alerts_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.label" "Alertas SMN"
    sw_state_set "module.icon" "lucide/shield-alert"
    sw_state_set "module.order" "$MODULE_ORDER"


    local order=10
    local i=1

    if (( ${#SMN_ALERT_HEADLINES[@]} == 0 )); then

        sw_state_set "detail" "Sin alertas activas"
        sw_state_set "detail.label" "Estado"
        
        MODULE_INTERVAL=21600

    else

        local headline
        local alert
        local status
        local severity
        local expires_raw
        local expires_local
        local summary

        for headline in "${SMN_ALERT_HEADLINES[@]}"; do

            alert="${SMN_BEST_JSON[${headline}]}"

            status="$(jq -r '.status // "WARNING"' <<< "${alert}")"
            severity="$(jq -r '.severity // "N/A"' <<< "${alert}")"
            expires_raw="$(jq -r '.expires // ""' <<< "${alert}")"
            expires_local="$(date -d "${expires_raw}" '+%Y-%m-%d %H:%M' 2>/dev/null)"
            [[ -z "${expires_local}" ]] && expires_local="${expires_raw}"

            summary="${headline} (${severity}) <br> hasta ${expires_local}"

            summary="$(sw_translate "${summary}")"

            sw_state_set "alert${i}" "${summary}"
            sw_state_set "alert${i}.label" "${status}"
            sw_state_set "alert${i}.order" "${order}"

            case "$status" in
                CRITICAL)
                    sw_state_set "alert${i}.color" "red"
                    ;;
                WARNING)
                    sw_state_set "alert${i}.color" "yellow"
                    ;;
                *)
                    sw_state_set "alert${i}.color" "white"
                    ;;
            esac

            (( order += 10 ))
            i=$(( i + 1 ))

        done
        
        MODULE_INTERVAL=1740

    fi

    # A PREVIOUS run may have had more active alerts than this one --
    # remove any leftover numbered fields beyond what we just set, so an
    # alert that's no longer active doesn't linger on the card forever.
    # This can't be a blanket sw_state_clear(): that would also wipe the
    # status/status_since/timestamp that sw_status_update() just set
    # moments ago (it needs the array to still hold the PREVIOUS status,
    # loaded via sw_state_load(), to detect a real transition -- clearing
    # before that point would make every run look like "first
    # execution").
    while [[ -n "$(sw_state_get "alert${i}")" ]]; do

        unset "SW_STATE[alert${i}]"
        unset "SW_STATE[alert${i}.label]"
        unset "SW_STATE[alert${i}.order]"

        i=$(( i + 1 ))

    done

}

smn_alerts_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "SMN alerts: ${#SMN_ALERT_HEADLINES[@]} active (${SMN_ALERTS_STATUS})"

}

sw_module_run() {

    sw_state_use "smn_alerts"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    smn_alerts_collect || return 1

    smn_alerts_dedupe

    smn_alerts_analyze

    sw_status_update "${SMN_ALERTS_STATUS}" || return 1

    smn_alerts_update_state

    sw_state_save

    smn_alerts_report

}
