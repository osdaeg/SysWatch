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

    local rrule=""
    local until=""

    local -a rule_parts

    local byday=""

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

            elif [[ "$line" == RRULE:* ]]; then
                rrule="${line#RRULE:}"

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

    # -------------------------------------------------------------------------
    # Expand simple yearly all-day recurrence.
    # -------------------------------------------------------------------------

    # Expand annual all-day recurrences when the original date is outside the display range.
    if ((event_end < range_start || event_start > range_end)) &&
        [[ "$all_day" == "true" ]]; then

        local interval="1"
        local rule_part
        local candidate_year
        local candidate_start=""
        local candidate_end=""
        local candidate_start_epoch
        local candidate_end_epoch
        local duration_days
        local month="${normalized_start:5:2}"
        local original_day="${normalized_start:8:2}"
        local ordinal=""
        local weekday=""
        local month_first
        local month_last
        local first_weekday
        local last_weekday
        local days_in_month
        local weekday_num
        local offset
        local occurrence_day
        local until_date=""
        local -a rule_parts
        local frequency=""

        IFS=';' read -ra rule_parts <<<"$rrule"

        for rule_part in "${rule_parts[@]}"; do
            case "$rule_part" in
            FREQ=*) frequency="${rule_part#FREQ=}" ;;
            INTERVAL=*) interval="${rule_part#INTERVAL=}" ;;
            BYDAY=*) byday="${rule_part#BYDAY=}" ;;
            UNTIL=*) until="${rule_part#UNTIL=}" ;;
            esac
        done

        if [[ -n "$rrule" ]]; then
        printf '[RRULE] Evento: %s | Regla: %s\n' \
            "${title:-SIN TÍTULO}" "$rrule" >>~/scripts/syswatch/helpers/rrule.txt
    fi

        if [[ "$frequency" == "YEARLY" ]] ||
            [[ "$frequency" == "MONTHLY" && "$interval" == "12" ]]; then

            duration_days=$(((event_end - event_start) / 86400))

            # Convert UNTIL to a calendar date.
            if [[ "$until" =~ ^[0-9]{8} ]]; then
                until_date="${until:0:4}-${until:4:2}-${until:6:2}"
            elif [[ -n "$until" ]]; then
                until_date="$(date -d "$until" '+%Y-%m-%d' 2>/dev/null)" || until_date=""
            fi

            for candidate_year in "$(date '+%Y')" "$(($(date '+%Y') + 1))"; do
                candidate_start=""

                if [[ -n "$byday" ]]; then
                    # Ordinal weekday: 1SU, 2WE, 4TH, -1MO, etc.
                    if [[ "$byday" =~ ^(-?[1-5])(SU|MO|TU|WE|TH|FR|SA)$ ]]; then
                        ordinal="${BASH_REMATCH[1]}"
                        weekday="${BASH_REMATCH[2]}"
                    else
                        # Unsupported BYDAY syntax: leave this occurrence alone.
                        continue
                    fi

                    month_first="${candidate_year}-${month}-01"
                    month_last="$(date -d "$month_first + 1 month - 1 day" '+%Y-%m-%d')" || continue
                    days_in_month="${month_last:8:2}"
                    first_weekday="$(date -d "$month_first" '+%w')" || continue

                    case "$weekday" in
                    SU) weekday_num=0 ;;
                    MO) weekday_num=1 ;;
                    TU) weekday_num=2 ;;
                    WE) weekday_num=3 ;;
                    TH) weekday_num=4 ;;
                    FR) weekday_num=5 ;;
                    SA) weekday_num=6 ;;
                    esac

                    if ((ordinal > 0)); then
                        offset=$(((weekday_num - first_weekday + 7) % 7))
                        occurrence_day=$((1 + offset + (ordinal - 1) * 7))
                    else
                        last_weekday="$(date -d "$month_last" '+%w')" || continue
                        offset=$(((last_weekday - weekday_num + 7) % 7))
                        occurrence_day=$((10#$days_in_month - offset))
                    fi

                    ((occurrence_day >= 1 && occurrence_day <= 10#$days_in_month)) || continue

                    candidate_start="$(printf '%04d-%02d-%02d' \
                        "$candidate_year" "$((10#$month))" "$occurrence_day")"

                else
                    # Annual recurrence on the original month/day.
                    candidate_start="$(date -d \
                        "${candidate_year}-${month}-${original_day}" \
                        '+%Y-%m-%d' 2>/dev/null)" || continue

                    # Reject dates normalized by GNU date, e.g. February 29
                    # becoming March 1 in a non-leap year.
                    [[ "${candidate_start:5:5}" == "${normalized_start:5:5}" ]] || continue
                fi

                if [[ -n "$until_date" && "$candidate_start" > "$until_date" ]]; then
                    continue
                fi

                candidate_end="$(date -d \
                    "$candidate_start + ${duration_days} days" '+%Y-%m-%d')" || continue

                candidate_start_epoch="$(date -d "$candidate_start" '+%s')" || continue
                candidate_end_epoch="$(date -d "$candidate_end" '+%s')" || continue

                if ((candidate_end_epoch >= range_start && candidate_start_epoch <= range_end)); then
                    normalized_start="$candidate_start"
                    normalized_end="$candidate_end"
                    event_start="$candidate_start_epoch"
                    event_end="$candidate_end_epoch"
                    break
                fi
            done
        fi
    fi

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

    rm -f ~/scripts/syswatch/helpers/rrule.txt

    for webcal in "${CALDAV_WEBCAL_SOURCES[@]}"; do

        IFS=$'\t' read -r displayname source <<<"$webcal"

        response="$(
            curl -fsS \
                --max-time 15 \
                "$source"
        )" || {
            WEBCAL_ERROR="Unable to download Webcal"
            echo "$WEBCAL_ERROR"
            return 1
        }

        webcal_collect_calendar "$response" "$displayname"

    done

}
