#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# ClamAV monitoring module
#
# Same architecture as rkhunter.sh/chkrootkit.sh: this module does NOT run
# a scan itself (a full clamscan takes far too long for SysWatch's own
# interval) -- it only reads the fixed-name log that clamav_scan.sh
# already wrote on its own cron schedule.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Clamav"
readonly MODULE_DESCRIPTION="ClamAV log monitoring (does not run scans itself)"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-3540}
MODULE_ORDER=${MODULE_ORDER:-56}
MODULE_REMOTE=${MODULE_REMOTE:-""}


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly CLAMAV_LOG="${CLAMAV_LOG:-/var/log/clamav/scan_downloads.log}"

# If the log hasn't been updated in this many hours, the scan's own cron
# job may have stopped running -- flag it (unless something worse already
# did).
readonly CLAMAV_MAX_AGE_HOURS="${CLAMAV_MAX_AGE_HOURS:-36}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

CLAMAV_INFECTED=0
CLAMAV_FILES_SCANNED=0
CLAMAV_DATA_SCANNED=""
CLAMAV_LOG_MTIME=0
CLAMAV_LOG_AGE_HOURS=0
CLAMAV_STATUS="${SW_STATUS_OK}"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

clamav_collect() {

    if [[ ! -r "${CLAMAV_LOG}" ]]; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "Cannot read ${CLAMAV_LOG} (missing, or the scan hasn't run yet)"

        return 1

    fi

    CLAMAV_LOG_MTIME="$(stat -c %Y "${CLAMAV_LOG}" 2>/dev/null)"
    CLAMAV_LOG_AGE_HOURS=$(( ( $(date +%s) - CLAMAV_LOG_MTIME ) / 3600 ))

    CLAMAV_INFECTED=0
    CLAMAV_FILES_SCANNED=0
    CLAMAV_DATA_SCANNED=""

    local found_summary="false"
    local line

    while IFS= read -r line
    do

        if [[ "${line}" =~ ^Infected\ files:\ *([0-9]+) ]]; then

            CLAMAV_INFECTED="${BASH_REMATCH[1]}"
            found_summary="true"

        elif [[ "${line}" =~ ^Scanned\ files:\ *([0-9]+) ]]; then

            CLAMAV_FILES_SCANNED="${BASH_REMATCH[1]}"

        elif [[ "${line}" =~ ^Data\ scanned:\ *(.+)$ ]]; then

            CLAMAV_DATA_SCANNED="${BASH_REMATCH[1]}"

        fi

    done < "${CLAMAV_LOG}"

    if [[ "${found_summary}" != "true" ]]; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "${CLAMAV_LOG} doesn't look like a clamscan summary (no 'Infected files:' line found)"

        return 1

    fi

}

clamav_analyze() {

    CLAMAV_STATUS="${SW_STATUS_OK}"

    if (( CLAMAV_INFECTED > 0 )); then

        CLAMAV_STATUS="${SW_STATUS_CRITICAL}"

    fi

    # A stale log (the scan's own cron seems to have stopped running) is
    # worth flagging, but shouldn't downgrade a worse status already
    # found.
    if (( CLAMAV_LOG_AGE_HOURS > CLAMAV_MAX_AGE_HOURS )) &&
       [[ "${CLAMAV_STATUS}" == "${SW_STATUS_OK}" ]]
    then

        CLAMAV_STATUS="${SW_STATUS_WARNING}"

    fi

}

clamav_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.label" "ClamAV"
    case "${CLAMAV_STATUS}" in
        OK)
            sw_state_set "module.icon" "lucide/shield-check"
            ;;
        WARNING)
            sw_state_set "module.icon" "lucide/shield-alert"
            ;;
        CRITiCAL)
            sw_state_set "module.icon" "lucide/shield-x"
            ;;
        *)
            sw_state_set "module.icon" "lucide/shield"
            ;;
    esac

    sw_state_set "module.order" "$MODULE_ORDER"

    sw_state_set "infected" "${CLAMAV_INFECTED}"
    sw_state_set "infected.label" "Infecciones"

    sw_state_set "files_scanned" "${CLAMAV_FILES_SCANNED}"
    sw_state_set "files_scanned.label" "Archivos escaneados"

    sw_state_set "data_scanned" "${CLAMAV_DATA_SCANNED}"
    sw_state_set "data_scanned.label" "Datos escaneados"

    sw_state_set "last_scan" "$(date -d "@${CLAMAV_LOG_MTIME}" '+%Y-%m-%d %H:%M' 2>/dev/null)"
    sw_state_set "last_scan.label" "Última corrida"

}

clamav_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "ClamAV: ${CLAMAV_INFECTED} infected, ${CLAMAV_FILES_SCANNED} files scanned, log age ${CLAMAV_LOG_AGE_HOURS}h (${CLAMAV_STATUS})"

}

sw_module_run() {

    sw_state_use "clamav-host"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi
    
    sw_state_load

    clamav_collect || return 1

    clamav_analyze

    sw_status_update "${CLAMAV_STATUS}" || return 1

    clamav_update_state

    sw_state_save

    clamav_report

}
