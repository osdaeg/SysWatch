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
readonly MODULE_DESCRIPTION="Date, uptime, etc"
readonly MODULE_VERSION="0.1.0"
readonly MODULE_INTERVAL=120

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

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

datetime_collect() {

    # Collect raw metrics here.
    # This step should not determine the module status.

    DATETIME_VALUE=0
    DT_UPTIME=$(uptime -p)
    DT_SECONDS=$(awk '{print $1}' /proc/uptime)
    DT_BOOT=$(uptime -s)
    DT_DAY=$(date "+%A %d de %B de %Y")
    DT_TIME=$(date "+%H:%M:%S")

}

datetime_analyze() {

    DATETIME_STATUS="${SW_STATUS_OK}"

    if (( DATETIME_VALUE >= DATETIME_CRITICAL )); then

        DATETIME_STATUS="${SW_STATUS_CRITICAL}"

    elif (( DATETIME_VALUE >= DATETIME_WARNING )); then

        DATETIME_STATUS="${SW_STATUS_WARNING}"

    fi

}

datetime_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata (consumed by lib/html.sh)
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "Fecha y hora"
    sw_state_set "module.icon" "lucide/clock"
    sw_state_set "module.order" "5"

    # -------------------------------------------------------------------------
    # Data
    # -------------------------------------------------------------------------

    #sw_state_set "value" "${DATETIME_VALUE}"

    #sw_state_set "value.label" "Value"
    #sw_state_set "value.widget" "line"
    #sw_state_set "value.unit" ""
    #sw_state_set "value.order" "10"
    #sw_state_set "value.warning" "${DATETIME_WARNING}"
    #sw_state_set "value.critical" "${DATETIME_CRITICAL}"
    
    sw_state_set "fecha" "${DT_DAY}"
    sw_state_set "fecha.label" "Fecha"
    sw_state_set "fecha.order" "10"
    
    sw_state_set "hora" "${DT_TIME}"
    sw_state_set "hora.label" "Hora"
    sw_state_set "hora.order" "20"
    
    sw_state_set "uptime" "${DT_UPTIME}"
    sw_state_set "uptime.label" "Tiempo de encendido"
    sw_state_set "uptime.order" "30"
    
    sw_state_set "boot" "${DT_BOOT}"
    sw_state_set "boot.label" "Encendido"
    sw_state_set "boot.order" "40"
    
    sw_state_set "segundos" "${DT_SECONDS}"
    sw_state_set "segundos.label" "Segundos"
    sw_state_set "segundos.order" "50"

}

datetime_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Example value: ${DATETIME_VALUE} (${DATETIME_STATUS})"

}

sw_module_run() {

    sw_state_use "datetime"
    sw_state_load

    datetime_collect

    datetime_analyze

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
