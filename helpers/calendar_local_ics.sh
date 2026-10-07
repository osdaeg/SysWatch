#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Webcal backend for Calendar module
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Backend variables
# -----------------------------------------------------------------------------

ICS_STATUS="${SW_STATUS_UNKNOWN}"
ICS_EVENTS=()
ICS_EVENT_COUNT=0
ICS_ERROR=""

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

ics_collect() {
    local ics_file
    local displayname

    while IFS=$'\t' read -r ics_file displayname; do
        [[ -z "$ics_file" ]] && continue
        [[ "$ics_file" == "# "* ]] && continue

        if [[ ! -f "$ics_file" ]]; then
            ICS_ERROR="Unable to read ICS file: $ics_file"
            return 1
        fi

        webcal_collect_calendar \
            "$(<"$ics_file")" \
            "$displayname" \
            "ICS_EVENTS"
    done <"${CONFIG_DIR}/ics.conf"
}
