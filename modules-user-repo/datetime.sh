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

readonly MODULE_NAME="Datetime"
readonly MODULE_SCRIPT="$(realpath "${BASH_SOURCE[0]}")"
readonly MODULE_DESCRIPTION="Date, uptime, etc"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-120}
MODULE_INTERVAL_NORMAL=${MODULE_INTERVAL_NORMAL:-}
MODULE_INTERVAL_ALT=${MODULE_INTERVAL_ALT:-}
MODULE_ORDER=${MODULE_ORDER:-5}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly DATETIME_WARNING="${DATETIME_WARNING:-80}"
readonly DATETIME_CRITICAL="${DATETIME_CRITICAL:-95}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

DATETIME_VALUE=0
DATETIME_STATUS="${SW_STATUS_UNKNOWN}"
export LC_TIME=es_AR.UTF-8

DT_TIMEZONE="unknown"
DT_NTP_SYNC="unknown"
DT_SYNCRO=""

DT_RTC_STATUS="unknown"
DT_RTC_DATE="unknown"
DT_RTC_TIME="unknown"
DT_RTC_DIFF=""
DT_RTC_BATTERY="unknown"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

datetime_collect() {

    # Collect raw metrics here.
    # This step should not determine the module status.

    DATETIME_VALUE=0

    DT_SECONDS=$(awk '{print $1}' /proc/uptime)

    # Tiempo encendido del sistema
    if [[ -r /proc/uptime ]]; then
        read -r uptime_seconds _ </proc/uptime
        uptime_seconds=${uptime_seconds%.*}

        days=$((uptime_seconds / 86400))
        hours=$((uptime_seconds % 86400 / 3600))
        minutes=$((uptime_seconds % 3600 / 60))

        DT_UPTIME="up"
        ((days > 0)) && DT_UPTIME+=" ${days} days,"
        ((hours > 0)) && DT_UPTIME+=" ${hours} hours"
        ((minutes > 0)) && DT_UPTIME+=" ${minutes} minutes"
    else
        DT_UPTIME="unknown"
    fi

    # Fecha y hora aproximadas del arranque
    if [[ -r /proc/uptime ]]; then
        boot_epoch=$(($(date +%s) - uptime_seconds))
        DT_BOOT=$(date -d "@${boot_epoch}" '+%Y-%m-%d %H:%M:%S')
    else
        DT_BOOT="unknown"
    fi

    DT_DAY=$(date "+%A %d de %B de %Y")
    DT_TIME=$(date "+%H:%M:%S")

    # Zona horaria configurada
    if command -v timedatectl >/dev/null 2>&1; then
        DT_TIMEZONE=$(timedatectl show -p Timezone --value 2>/dev/null)
        [[ -n "$DT_TIMEZONE" ]] || DT_TIMEZONE="unknown"

        # Estado de sincronización del reloj
        DT_NTP_SYNC=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)

        case "$DT_NTP_SYNC" in
        yes)
            DT_NTP_SYNC="synchronized"
            DT_SYNCRO=0
            ;;
        no)
            DT_NTP_SYNC="not synchronized"
            DT_SYNCRO=1
            ;;
        *)
            DT_NTP_SYNC="unknown"
            DT_SYNCRO=""
            ;;
        esac

    else
        DT_TIMEZONE="unknown"
        DT_NTP_SYNC="unknown"
    fi

    # RTC: disponibilidad, fecha, hora y batería
    local rtc_path=""
    local rtc_date=""
    local rtc_time=""
    local rtc_epoch=""
    local system_epoch=""

    DT_RTC_STATUS="unavailable"
    DT_RTC_DATE="unknown"
    DT_RTC_TIME="unknown"
    DT_RTC_DIFF=""
    DT_RTC_BATTERY="unknown"

    for rtc in /sys/class/rtc/rtc*; do
        [[ -d "$rtc" ]] || continue

        if [[ -r "$rtc/date" && -r "$rtc/time" ]]; then
            rtc_path="$rtc"
            break
        fi
    done

    if [[ -n "$rtc_path" ]]; then
        rtc_date=$(<"$rtc_path/date")
        rtc_time=$(<"$rtc_path/time")

        if [[ "$rtc_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ &&
            "$rtc_time" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then

            DT_RTC_STATUS="available"
            DT_RTC_DATE="$rtc_date"
            DT_RTC_TIME="$rtc_time"

            # Comparación aproximada en UTC.
            rtc_epoch=$(date -u -d "${rtc_date} ${rtc_time}" +%s 2>/dev/null)
            system_epoch=$(date -u +%s)

            if [[ "$rtc_epoch" =~ ^[0-9]+$ &&
                "$system_epoch" =~ ^[0-9]+$ ]]; then
                DT_RTC_DIFF=$((rtc_epoch - system_epoch))
            fi
        fi

        # Indicador de batería, si el kernel lo proporciona.
        if [[ -r /proc/driver/rtc ]]; then
            local battery_status
            battery_status=$(awk -F: '
                /^batt_status[[:space:]]*:/ {
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
                    print $2
                    exit
                }
            ' /proc/driver/rtc)

            [[ -n "$battery_status" ]] &&
                DT_RTC_BATTERY="$battery_status"
        fi
    fi

    #echo "$DT_RTC_STATUS - $DT_RTC_DATE - $DT_RTC_TIME - $DT_RTC_DIFF - $DT_RTC_BATTERY"

}

datetime_analyze() {

    DATETIME_STATUS="${SW_STATUS_OK}"

    if [[ "${DT_SYNCRO}" == "1" ]] &&
        sw_csv_all_above \
            datetime \
            sincro \
            1 \
            "${DATETIME_SYNCRO_SUSTAINED_SAMPLES}"; then
        DATETIME_STATUS="${SW_STATUS_WARNING}"
    fi

    if [[ "${DT_RTC_STATUS}" == "available" &&
        -n "${DT_RTC_DIFF}" ]]; then

        local rtc_diff_abs=${DT_RTC_DIFF#-}

        if ((rtc_diff_abs >= DATETIME_RTC_DIFF_THRESHOLD)) &&
            sw_csv_all_above \
                datetime \
                rtc \
                "${DATETIME_RTC_DIFF_THRESHOLD}" \
                "$((DATETIME_RTC_DIFF_SUSTAINED_SAMPLES - 1))"; then
            DATETIME_STATUS="${SW_STATUS_WARNING}"
        fi
    fi

}

datetime_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata (consumed by lib/html.sh)
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "$(sw_translate "Date & time")"
    sw_state_set "module.icon" "lucide/clock"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Data
    # -------------------------------------------------------------------------

    #sw_state_set "value" "${DATETIME_VALUE}"

    #sw_state_set "value.label" "$(sw_translate "Value")"
    #sw_state_set "value.widget" "line"
    #sw_state_set "value.unit" ""
    #sw_state_set "value.order" "10"
    #sw_state_set "value.warning" "${DATETIME_WARNING}"
    #sw_state_set "value.critical" "${DATETIME_CRITICAL}"

    sw_state_set "fecha" "${DT_DAY}"
    sw_state_set "fecha.label" "$(sw_translate "Date")"
    sw_state_set "fecha.order" "10"

    sw_state_set "hora" "${DT_TIME}"
    sw_state_set "hora.label" "$(sw_translate "Time")"
    sw_state_set "hora.order" "20"

    sw_state_set "timezone" "${DT_TIMEZONE}"
    sw_state_set "timezone.label" "$(sw_translate "Time zone")"
    sw_state_set "timezone.order" "25"

    sw_state_set "ntp_sync" "$(sw_translate "${DT_NTP_SYNC}")"
    sw_state_set "ntp_sync.label" "$(sw_translate "Clock synchronization")"
    sw_state_set "ntp_sync.order" "27"

    sw_state_set "uptime" "${DT_UPTIME}"
    sw_state_set "uptime.label" "$(sw_translate "Uptime")"
    sw_state_set "uptime.order" "30"

    sw_state_set "boot" "${DT_BOOT}"
    sw_state_set "boot.label" "$(sw_translate "Boot time")"
    sw_state_set "boot.order" "40"

    sw_state_set "segundos" "${DT_SECONDS}"
    sw_state_set "segundos.label" "$(sw_translate "Seconds")"
    sw_state_set "segundos.order" "50"

    # -------------------------------------------------------------------------
    # Real-time clock (RTC)
    # -------------------------------------------------------------------------

    sw_state_set "rtc_status" "$(sw_translate "${DT_RTC_STATUS}")"
    sw_state_set "rtc_status.label" "$(sw_translate "RTC status")"
    sw_state_set "rtc_status.order" "60"

    if [[ "${DT_RTC_STATUS}" == "available" ]]; then
        sw_state_set "rtc_status.color" "green"
    else
        sw_state_set "rtc_status.color" "red"
    fi

    sw_state_set "rtc_date" "${DT_RTC_DATE}"
    sw_state_set "rtc_date.label" "$(sw_translate "RTC date")"
    sw_state_set "rtc_date.order" "70"

    sw_state_set "rtc_time" "${DT_RTC_TIME} UTC"
    sw_state_set "rtc_time.label" "$(sw_translate "RTC time")"
    sw_state_set "rtc_time.order" "80"

    if [[ -n "${DT_RTC_DIFF}" ]]; then
        sw_state_set "rtc_diff" "${DT_RTC_DIFF} s"
    else
        sw_state_set "rtc_diff" "unknown"
    fi
    sw_state_set "rtc_diff.label" "$(sw_translate "RTC/system difference")"
    sw_state_set "rtc_diff.order" "90"

    sw_state_set "rtc_battery" "$(sw_translate "${DT_RTC_BATTERY}")"
    sw_state_set "rtc_battery.label" "$(sw_translate "RTC battery")"
    sw_state_set "rtc_battery.order" "100"

}

datetime_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Date & time: ${DATETIME_VALUE} (${DATETIME_STATUS})"

}

sw_module_run() {

    sw_state_use "datetime"
    sw_state_load

    datetime_collect

    datetime_analyze

    if [[ -n "${DT_SYNCRO}" ]]; then
        sw_csv_append datetime sincro "${DT_SYNCRO}"
    fi

    if [[ "${DT_RTC_STATUS}" == "available" &&
        -n "${DT_RTC_DIFF}" ]]; then
        sw_csv_append datetime rtc "${DT_RTC_DIFF}"
    fi

    sw_status_update "${DATETIME_STATUS}" || return 1

    datetime_update_state

    sw_state_save

    datetime_report

    # Optional: append to CSV history for sparkline widgets.
    #
    # sw_csv_append \
    #     "example" \
    #     "value" \
    #     "${DATETIME_VALUE}"

}
