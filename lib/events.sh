#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Event handling
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

sw_events_file() {

    printf '%s/events.log\n' "$LOG_DIR"

}

sw_event() {

    local level="$1"
    local module="$2"
    local message="$3"

    sw_mkdir "$LOG_DIR"

    printf '%s %-8s %-15s %s\n' \
        "$(sw_timestamp)" \
        "$level" \
        "$module" \
        "$message" \
        >> "$(sw_events_file)"

    #
    # Optional notification backend.
    #
    # events.sh does not know (and should not know) whether Gotify, ntfy,
    # or nothing at all is listening. If some lib/notify_*.sh happened to
    # be sourced and defines sw_notify_dispatch(), we call it; otherwise
    # this is a no-op. Either way, a backend failure (network down, bad
    # token, curl missing) must never abort the module/launcher that
    # triggered the event -- monitoring must keep running even if
    # notifications can't be delivered.
    #

    if declare -F sw_notify_dispatch >/dev/null; then

        sw_notify_dispatch "${level}" "${module}" "${message}" || true

    fi

}

sw_event_info() {

    sw_event "INFO" "$1" "$2"

}

sw_event_warning() {

    sw_event "WARNING" "$1" "$2"

}

sw_event_error() {

    sw_event "ERROR" "$1" "$2"

}

sw_event_critical() {

    sw_event "CRITICAL" "$1" "$2"

}