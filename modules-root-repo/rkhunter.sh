#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# rkhunter monitoring module
#
# This module does NOT run rkhunter itself -- a full scan takes minutes and
# is heavy on I/O, so it has no business running on SysWatch's own interval.
# rkhunter should keep running on its OWN schedule (its usual daily cron
# job, e.g. `rkhunter --cronjob --report-warnings-only`), and this module
# just reads the log that scan already produced.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Rkhunter"
readonly MODULE_DESCRIPTION="rkhunter log monitoring (does not run scans itself)"
readonly MODULE_VERSION="0.1.0"
readonly MODULE_INTERVAL=86400

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly RKHUNTER_LOG="${RKHUNTER_LOG:-/var/log/rkhunter.log}"

# If the log hasn't been updated in this many hours, something is off with
# rkhunter's own cron job -- flag it (as long as nothing worse already did).
readonly RKHUNTER_MAX_AGE_HOURS="${RKHUNTER_MAX_AGE_HOURS:-36}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

RKHUNTER_FILES_CHECKED=0
RKHUNTER_SUSPECT_FILES=0
RKHUNTER_ROOTKITS_CHECKED=0
RKHUNTER_POSSIBLE_ROOTKITS=0
RKHUNTER_LOG_MTIME=0
RKHUNTER_LOG_AGE_HOURS=0
RKHUNTER_STATUS="${SW_STATUS_OK}"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

rkhunter_collect() {

    if [[ ! -r "${RKHUNTER_LOG}" ]]; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "Cannot read ${RKHUNTER_LOG} (missing, or rkhunter hasn't run yet)"

        return 1

    fi

    RKHUNTER_LOG_MTIME="$(stat -c %Y "${RKHUNTER_LOG}" 2>/dev/null)"
    RKHUNTER_LOG_AGE_HOURS=$(( ( $(date +%s) - RKHUNTER_LOG_MTIME ) / 3600 ))

    RKHUNTER_FILES_CHECKED=0
    RKHUNTER_SUSPECT_FILES=0
    RKHUNTER_ROOTKITS_CHECKED=0
    RKHUNTER_POSSIBLE_ROOTKITS=0

    # Scan the whole file and keep the LAST match of each summary field --
    # this naturally does the right thing whether the log gets overwritten
    # each run (rkhunter's default) or appended across multiple runs.
    local line

    while IFS= read -r line
    do

        if [[ "${line}" =~ Files\ checked:\ *([0-9]+) ]]; then

            RKHUNTER_FILES_CHECKED="${BASH_REMATCH[1]}"

        elif [[ "${line}" =~ Suspect\ files:\ *([0-9]+) ]]; then

            RKHUNTER_SUSPECT_FILES="${BASH_REMATCH[1]}"

        elif [[ "${line}" =~ Rootkits\ checked\ *:\ *([0-9]+) ]]; then

            RKHUNTER_ROOTKITS_CHECKED="${BASH_REMATCH[1]}"

        elif [[ "${line}" =~ Possible\ rootkits:\ *([0-9]+) ]]; then

            RKHUNTER_POSSIBLE_ROOTKITS="${BASH_REMATCH[1]}"

        fi

    done < "${RKHUNTER_LOG}"

}

rkhunter_analyze() {

    RKHUNTER_STATUS="${SW_STATUS_OK}"

    if (( RKHUNTER_POSSIBLE_ROOTKITS > 0 )); then

        RKHUNTER_STATUS="${SW_STATUS_CRITICAL}"

    elif (( RKHUNTER_SUSPECT_FILES > 0 )); then

        RKHUNTER_STATUS="${SW_STATUS_WARNING}"

    fi

    # A stale log (rkhunter's own cron seems to have stopped running) is
    # worth flagging, but shouldn't downgrade a worse status already found.
    if (( RKHUNTER_LOG_AGE_HOURS > RKHUNTER_MAX_AGE_HOURS )) &&
       [[ "${RKHUNTER_STATUS}" == "${SW_STATUS_OK}" ]]
    then

        RKHUNTER_STATUS="${SW_STATUS_WARNING}"

    fi

}

rkhunter_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.label" "RKHunter"
    sw_state_set "module.icon" "lucide/shield"
    sw_state_set "module.order" "55"

    sw_state_set "possible_rootkits" "${RKHUNTER_POSSIBLE_ROOTKITS}"
    sw_state_set "possible_rootkits.label" "Rootkits posibles"

    sw_state_set "suspect_files" "${RKHUNTER_SUSPECT_FILES}"
    sw_state_set "suspect_files.label" "Archivos sospechosos"

    sw_state_set "files_checked" "${RKHUNTER_FILES_CHECKED}"
    sw_state_set "files_checked.label" "Archivos chequeados"

    sw_state_set "rootkits_checked" "${RKHUNTER_ROOTKITS_CHECKED}"
    sw_state_set "rootkits_checked.label" "Rootkits chequeados"

    sw_state_set "last_scan" "$(date -d "@${RKHUNTER_LOG_MTIME}" '+%Y-%m-%d %H:%M' 2>/dev/null)"
    sw_state_set "last_scan.label" "Última corrida"

}

rkhunter_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Rkhunter: ${RKHUNTER_POSSIBLE_ROOTKITS} possible rootkit(s), ${RKHUNTER_SUSPECT_FILES} suspect file(s), log age ${RKHUNTER_LOG_AGE_HOURS}h (${RKHUNTER_STATUS})"

}

sw_module_run() {

    sw_state_use "rkhunter"
    sw_state_load

    rkhunter_collect || return 1

    rkhunter_analyze

    sw_status_update "${RKHUNTER_STATUS}" || return 1

    rkhunter_update_state

    sw_state_save

    rkhunter_report

}
