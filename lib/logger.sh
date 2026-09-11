#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Logging functions
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

sw_log_rename() {
    
    local ayer
    ayer=$(date -d "yesterday" '+%Y-%m-%d')
    
    local archivo_origen="$(sw_log_file)"
    local archivo_destino="${LOG_DIR}/syswatch-${ayer}.log"
    
    if [ ! -f "$archivo_origen" ]; then
        return 1
    fi
    
    if [ -f "$archivo_destino" ]; then
        return 0
    else    
        if mv "$archivo_origen" "$archivo_destino"; then
            return 0
        else
            return 1
        fi
    fi

}


sw_log_file() {

    printf '%s\n' "${LOG_DIR}/syswatch.log"

}

sw_log() {

    local level="$1"
    local module="$2"
    local message="$3"

    sw_mkdir "$LOG_DIR"

    printf '%s %-8s %-15s %s\n' \
        "$(sw_timestamp)" \
        "$level" \
        "$module" \
        "$message" \
        >> "$(sw_log_file)"

}

sw_log_execution() {

    sw_mkdir "$LOG_DIR"

    printf '\n============================================================\n' \
        >> "$(sw_log_file)"

    printf 'SysWatch v%s - Execution started - %s\n' \
        "$SW_VERSION" \
        "$(sw_timestamp)" \
        >> "$(sw_log_file)"

    printf '============================================================\n' \
        >> "$(sw_log_file)"

}

sw_log_debug() {

    [[ "${LOG_LEVEL}" == "DEBUG" ]] || return 0

    sw_log "DEBUG" "$1" "$2"

}

sw_log_info() {

    sw_log "INFO" "$1" "$2"

}

sw_log_warning() {

    sw_log "WARNING" "$1" "$2"

}

sw_log_critical() {

    sw_log "CRITICAL" "$1" "$2"

}

sw_log_error() {

    sw_log "ERROR" "$1" "$2"

}