#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Speedtest monitoring module
#
# Purely informational (no thresholds/alerting): shows current download/
# upload/ping/loss. Uses the official Ookla `speedtest` CLI.
#
# Throttled independently of MODULE_INTERVAL: running a full speed test
# every couple of minutes would burn real bandwidth for no reason, so
# this stores the wall-clock time of its last REAL run in its own state
# and skips actual execution (leaving the previous reading on the card
# untouched) until SPEEDTEST_INTERVAL_MINUTES has actually elapsed --
# regardless of how often this module happens to be invoked.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Speedtest"
readonly MODULE_DESCRIPTION="Internet speed monitoring (Ookla speedtest CLI)"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-120}
MODULE_ORDER=${MODULE_ORDER:-70}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly SPEEDTEST_INTERVAL_MINUTES="${SPEEDTEST_INTERVAL_MINUTES:-360}"
readonly SPEEDTEST_TIMEOUT_SECONDS="${SPEEDTEST_TIMEOUT_SECONDS:-120}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

SPEEDTEST_DOWNLOAD_MBPS=""
SPEEDTEST_UPLOAD_MBPS=""
SPEEDTEST_PING_MS=""
SPEEDTEST_PACKET_LOSS=""
SPEEDTEST_EXTERNAL_IP=""

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

speedtest_should_run() {

    local last_run
    last_run="$(sw_state_get "last_run_epoch")"

    # Never run before -- do it now.
    [[ -z "${last_run}" ]] && return 0

    local now elapsed_minutes
    now="$(date +%s)"
    elapsed_minutes=$(( (now - last_run) / 60 ))

    (( elapsed_minutes >= SPEEDTEST_INTERVAL_MINUTES ))

}

speedtest_collect() {

    sw_require_command speedtest || return 127
    sw_require_command jq || return 127

    local response
    response="$(
        timeout "${SPEEDTEST_TIMEOUT_SECONDS}" \
            speedtest --accept-license --accept-gdpr -f json \
            2>/dev/null
    )"

    if [[ -z "${response}" ]]; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "speedtest produced no output (network issue, or the CLI isn't installed/licensed)"

        return 1

    fi

    # bandwidth comes in bytes/sec from the Ookla CLI -- convert to Mbps.
    SPEEDTEST_DOWNLOAD_MBPS="$(
        jq -r '((.download.bandwidth // 0) * 8 / 1000000) | (. * 10 | round) / 10' <<< "${response}"
    )"
    SPEEDTEST_UPLOAD_MBPS="$(
        jq -r '((.upload.bandwidth // 0) * 8 / 1000000) | (. * 10 | round) / 10' <<< "${response}"
    )"
    SPEEDTEST_PING_MS="$(jq -r '.ping.latency // 0' <<< "${response}")"
    SPEEDTEST_PACKET_LOSS="$(jq -r '.packetLoss // 0' <<< "${response}")"
    SPEEDTEST_EXTERNAL_IP="$(jq -r '.interface.externalIp // "unknown"' <<< "${response}")"

}

speedtest_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.label" "$(sw_translate "Speedtest")"
    sw_state_set "module.icon" "lucide/gauge"
    sw_state_set "module.order" "$MODULE_ORDER"

    sw_state_set "download" "${SPEEDTEST_DOWNLOAD_MBPS}"
    sw_state_set "download.label" "$(sw_translate "Download")"
    sw_state_set "download.unit" "Mbps"
    sw_state_set "download.order" "10"
    sw_state_set "download.widget" "line"
    sw_state_set "download.scale" "fixed"
    sw_state_set "download.min" "0"
    sw_state_set "download.max" "350"

    sw_state_set "upload" "${SPEEDTEST_UPLOAD_MBPS}"
    sw_state_set "upload.label" "$(sw_translate "Upload")"
    sw_state_set "upload.unit" "Mbps"
    sw_state_set "upload.order" "20"
    sw_state_set "upload.widget" "line"
    sw_state_set "upload.scale" "fixed"
    sw_state_set "upload.min" "0"
    sw_state_set "upload.max" "80"

    sw_state_set "ping" "${SPEEDTEST_PING_MS}"
    sw_state_set "ping.label" "Ping"
    sw_state_set "ping.unit" "ms"
    sw_state_set "ping.order" "30"

    sw_state_set "loss" "${SPEEDTEST_PACKET_LOSS}"
    sw_state_set "loss.label" "$(sw_translate "Lost")"
    sw_state_set "loss.unit" "%"
    sw_state_set "loss.order" "40"

    sw_state_set "extip" "${SPEEDTEST_EXTERNAL_IP}"
    sw_state_set "extip.label" "$(sw_translate "External IP")"
    sw_state_set "extip.order" "50"

    sw_state_set "last_run_epoch" "$(date +%s)"
    sw_state_set "last_run_epoch.hidden" "true"

}

speedtest_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Speedtest: down=${SPEEDTEST_DOWNLOAD_MBPS}Mbps up=${SPEEDTEST_UPLOAD_MBPS}Mbps ping=${SPEEDTEST_PING_MS}ms"

}

sw_module_run() {

    sw_state_use "speedtest"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi
    
    sw_state_load

    if ! speedtest_should_run; then

        sw_log_info \
            "${MODULE_NAME}" \
            "Skipping, last real run was too recent (interval ${SPEEDTEST_INTERVAL_MINUTES}m)"

        return 0

    fi

    speedtest_collect || return 1

    sw_status_update "${SW_STATUS_OK}" || return 1

    speedtest_update_state

    sw_state_save

    local dl_csv

    dl_csv="$(awk \
            -v value="$SPEEDTEST_DOWNLOAD_MBPS" \
            'BEGIN { printf "%.0f", value }')"

    sw_csv_append \
        "speedtest" \
        "download" \
        "$dl_csv"

    local ul_csv
    
    ul_csv="$(awk \
            -v value="$SPEEDTEST_UPLOAD_MBPS" \
            'BEGIN { printf "%.0f", value }')"

    sw_csv_append \
        "speedtest" \
        "upload" \
        "$ul_csv"    

    speedtest_report

}
