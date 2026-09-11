#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Notification backend (Gotify)
#
# Modules never call this library directly, and this library never knows
# which modules exist. It only exposes sw_notify_dispatch(), a single,
# stable entry point that events.sh calls -- if this file happens to be
# loaded -- every time sw_event() records something. This mirrors how
# modules.sh discovers sw_module_run() without knowing the module ahead
# of time: events.sh discovers sw_notify_dispatch() the same way.
#
# If a different backend is needed later (ntfy, Telegram, email...), it
# should be a new lib/notify_*.sh exposing the same sw_notify_dispatch()
# entry point, without touching events.sh or any module.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

: "${NOTIFY_MIN_LEVEL:=WARNING}"
: "${NOTIFY_CURL_TIMEOUT:=5}"

# -----------------------------------------------------------------------------
# Private
# -----------------------------------------------------------------------------

_sw_notify_level_rank() {

    case "$1" in

        DEBUG)     printf '0\n' ;;
        INFO)      printf '1\n' ;;
        OK)        printf '1\n' ;;
        UNKNOWN)   printf '1\n' ;;
        DISABLED)  printf '1\n' ;;
        WARNING)   printf '2\n' ;;
        ERROR)     printf '3\n' ;;
        CRITICAL)  printf '3\n' ;;
        *)         printf '1\n' ;;

    esac

}

_sw_notify_priority() {

    case "$1" in

        CRITICAL) printf '8\n' ;;
        ERROR)    printf '7\n' ;;
        WARNING)  printf '5\n' ;;
        *)        printf '3\n' ;;

    esac

}

_sw_notify_should_send() {

    local level="$1"

    [[ "${ENABLE_GOTIFY}" == "true" ]] || return 1

    (( $(_sw_notify_level_rank "${level}") >= $(_sw_notify_level_rank "${NOTIFY_MIN_LEVEL}") ))

}

# -----------------------------------------------------------------------------
# Public
# -----------------------------------------------------------------------------

sw_notify_dispatch() {

    local level="$1"
    local module="$2"
    local message="$3"

    _sw_notify_should_send "${level}" || return 0

    command -v curl >/dev/null 2>&1 || {

        sw_log_warning \
            "Notify" \
            "curl not found, cannot dispatch Gotify notification"

        return 1

    }

    local priority
    priority="$(_sw_notify_priority "${level}")"

    local http_code

    http_code="$(
        curl \
            --silent \
            --show-error \
            --max-time "${NOTIFY_CURL_TIMEOUT}" \
            --output /dev/null \
            --write-out '%{http_code}' \
            --form "title=[${level}] ${module}" \
            --form "message=${message}" \
            --form "priority=${priority}" \
            "${GOTIFY_URL%/}/message?token=${GOTIFY_TOKEN}" \
            2>>"$(sw_log_file)"
    )"

    if [[ "${http_code}" != "200" ]]; then

        sw_log_warning \
            "Notify" \
            "Gotify request failed (HTTP ${http_code:-?})"

        return 1

    fi

}
