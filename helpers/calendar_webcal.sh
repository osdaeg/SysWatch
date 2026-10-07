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

WEBCAL_STATUS="${SW_STATUS_UNKNOWN}"
WEBCAL_EVENTS=()
WEBCAL_EVENT_COUNT=0
WEBCAL_ERROR=""

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

webcal_collect_calendar() {

    local calendar_data="$1"
    local displayname="$2"
    local events_array="${3:-WEBCAL_EVENTS}"

    local event

    while IFS= read -r -d $'\034' event; do

        [[ -z "$event" ]] && continue

        webcal_parse_event "$event" "$displayname" "$events_array"

    done < <(
        printf '%s\n' "$calendar_data" |
            awk '
            /BEGIN:VEVENT/ {
                event = ""
                inside = 1
            }

            inside {
                event = event $0 "\n"
            }

            /END:VEVENT/ {
                printf "%s", event
                printf "%c", 28
                inside = 0
            }
        '
    )

}

webcal_parse_event() {

    local calendar_data="$1"
    local displayname="$2"
    local events_array="${3:-WEBCAL_EVENTS}"

    local start=""
    local end=""
    local title=""
    local all_day="false"

    local line
    local unfolded=""
    local previous=""

    local start_tz=""
    local end_tz=""

    calendar_data="${calendar_data//$'\r'/}"

    # -------------------------------------------------------------------------
    # Unfold iCalendar lines.
    #
    # RFC 5545 uses a space or tab at the beginning of a line to indicate that
    # it continues the previous line.
    # -------------------------------------------------------------------------

    while IFS= read -r line || [[ -n "$line" ]]; do

        if [[ "$line" =~ ^[[:space:]] ]]; then

            previous+="${line:1}"

        else

            if [[ -n "$previous" ]]; then
                unfolded+="${previous}"$'\n'
            fi

            previous="$line"

        fi

    done <<<"$calendar_data"

    if [[ -n "$previous" ]]; then
        unfolded+="${previous}"$'\n'
    fi

    # -------------------------------------------------------------------------
    # Extract VEVENT properties.
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    # Extract VEVENT properties.
    #
    # Ignore VTIMEZONE and any other VCALENDAR components. Only properties
    # belonging to VEVENT are relevant here.
    # -------------------------------------------------------------------------
    local in_vevent=false

    while IFS= read -r line; do
        #line="${line%$'\n'}"

        case "$line" in
        BEGIN:VEVENT)
            in_vevent=true
            ;;

        END:VEVENT)
            in_vevent=false
            ;;

        *)
            [[ "$in_vevent" == true ]] || continue

            if [[ "$line" == DTSTART\;VALUE=DATE:* ]]; then
                start="${line#*:}"
                all_day="true"

            elif [[ "$line" == DTSTART\;TZID=* ]]; then
                start="${line#*:}"
                start_tz="${line#*TZID=}"
                start_tz="${start_tz%%:*}"

            elif [[ "$line" == DTSTART:* ]]; then
                start="${line#*:}"

            elif [[ "$line" == DTEND\;VALUE=DATE:* ]]; then
                end="${line#*:}"

            elif [[ "$line" == DTEND\;TZID=* ]]; then
                end="${line#*:}"
                end_tz="${line#*TZID=}"
                end_tz="${end_tz%%:*}"

            elif [[ "$line" == DTEND:* ]]; then
                end="${line#*:}"

            elif [[ "$line" == SUMMARY:* ]]; then
                title="${line#*:}"
            fi
            ;;
        esac
    done <<<"$unfolded"

    # -------------------------------------------------------------------------
    # Ignore malformed events.
    # -------------------------------------------------------------------------

    if [[ -z "$start" || -z "$title" ]]; then
        return
    fi

    [[ -z "$end" ]] && end="$start"

    # -------------------------------------------------------------------------
    # Normalize date/time values.
    # -------------------------------------------------------------------------

    local normalized_start
    local normalized_end

    if [[ "$all_day" == "true" ]]; then

        normalized_start="$(
            date \
                -d "${start:0:4}-${start:4:2}-${start:6:2}" \
                '+%Y-%m-%d'
        )" || return

        normalized_end="$(
            date \
                -d "${end:0:4}-${end:4:2}-${end:6:2}" \
                '+%Y-%m-%d'
        )" || return

    else

        normalized_start="$(webcal_normalize_datetime "$start" "$start_tz")" || return
        normalized_end="$(webcal_normalize_datetime "$end" "$end_tz")" || return
    fi

    # -------------------------------------------------------------------------
    # Append normalized event.
    #
    # Format:
    #
    # start<TAB>end<TAB>title<TAB>calendar<TAB>all_day
    # -------------------------------------------------------------------------

    local range_start
    local range_end

    range_start="$(date '+%s')"
    range_end="$(date -d 'tomorrow 23:59:59' '+%s')"

    local event_start
    local event_end
    local -n events="$events_array"

    event_start="$(date -d "$normalized_start" '+%s')" || return
    event_end="$(date -d "$normalized_end" '+%s')" || return

    # Ignore events outside the requested time range.
    if ((event_end < range_start || event_start > range_end)); then
        return
    fi

    events+=(
        "${normalized_start}"$'\t'"${normalized_end}"$'\t'"${title}"$'\t'"${displayname}"$'\t'"${all_day}"
    )

}

webcal_normalize_datetime() {

    local timezone="${2:-}"

    local value="$1"

    local timestamp
    local datetime

    if [[ -n "$timezone" && "$value" =~ ^[0-9]{8}T[0-9]{6}$ ]]; then
        local timestamp

        timestamp="$(
            TZ="$timezone" date \
                -d "${value:0:4}-${value:4:2}-${value:6:2} ${value:9:2}:${value:11:2}:${value:13:2}" \
                +%s
        )" || return 1

        date -d "@${timestamp}" --iso-8601=seconds
        return
    fi

    # -------------------------------------------------------------------------
    # UTC.
    #
    # Example:
    #
    # 20260930T210000Z
    # -------------------------------------------------------------------------

    if [[ "$value" =~ ^([0-9]{8})T([0-9]{6})Z$ ]]; then

        datetime="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"

        timestamp="$(
            date \
                -u \
                -d "${datetime:0:4}-${datetime:4:2}-${datetime:6:2} ${datetime:9:2}:${datetime:11:2}:${datetime:13:2}" \
                +%s
        )" || return 1

        date -d "@${timestamp}" --iso-8601=seconds

        return

    fi

    # -------------------------------------------------------------------------
    # Floating local time.
    #
    # Example:
    #
    # 20260930T153000
    # -------------------------------------------------------------------------

    if [[ "$value" =~ ^[0-9]{8}T[0-9]{6}$ ]]; then

        date \
            -d "${value:0:4}-${value:4:2}-${value:6:2} ${value:9:2}:${value:11:2}:${value:13:2}" \
            --iso-8601=seconds

        return

    fi

    return 1
}

webcal_get_calendars() {
    printf '%s\n' "${CALDAV_WEBCAL_SOURCES[@]}"
}

webcal_collect() {

    local displayname
    local source

    for webcal in "${CALDAV_WEBCAL_SOURCES[@]}"; do

        IFS=$'\t' read -r displayname source <<<"$webcal"

        response="$(
            curl -fsS \
                --max-time 15 \
                "$source"
        )" || {
            WEBCAL_ERROR="Unable to download Webcal"
            return 1
        }

        webcal_collect_calendar "$response" "$displayname"

    done

}
