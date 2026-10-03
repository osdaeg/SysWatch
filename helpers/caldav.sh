#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# CalDAV backend for Calendar module
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Backend variables
# -----------------------------------------------------------------------------

CALDAV_STATUS="${SW_STATUS_UNKNOWN}"
CALDAV_EVENTS=()
CALDAV_EVENT_COUNT=0
CALDAV_ERROR=""

CALDAV_WEBCAL_SOURCES=()
CALDAV_CALENDARS=()

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

caldav_discover_calendars() {

    local response

    CALDAV_WEBCAL_SOURCES=()
    CALDAV_CALENDARS=()

    response="$(
        curl -fsS \
            --max-time 15 \
            -u "${CALDAV_USERNAME}:${CALDAV_PASSWORD}" \
            -X PROPFIND \
            -H 'Content-Type: application/xml; charset=utf-8' \
            -H 'Depth: 1' \
            --data-binary @- \
            "$CALDAV_URL" <<'EOF'
<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:"
    xmlns:C="urn:ietf:params:xml:ns:caldav"
    xmlns:CS="http://calendarserver.org/ns/">

    <D:prop>
        <D:resourcetype/>
        <D:displayname/>
        <C:supported-calendar-component-set/>
        <CS:source/>
    </D:prop>

</D:propfind>
EOF
    )" || {

        CALDAV_ERROR="Unable to discover CalDAV calendars"
        return 1
    }

    if ! xmllint --noout - >/dev/null 2>&1 <<<"$response"; then

        CALDAV_ERROR="Invalid CalDAV discovery response"
        return 1

    fi

    local response_count
    local i

    response_count="$(
        xmllint \
            --xpath \
            'count(//*[local-name()="response"])' \
            - \
            <<<"$response" \
            2>/dev/null
    )"

    for ((i = 1; i <= response_count; i++)); do

        local href
        local displayname
        local is_calendar
        local is_subscribed
        local has_vevent
        local source

        href="$(
            xmllint \
                --xpath \
                "string((//*[local-name()='response'])[${i}]/*[local-name()='href'])" \
                - \
                <<<"$response" \
                2>/dev/null
        )"

        displayname="$(
            xmllint \
                --xpath \
                "string((//*[local-name()='response'])[${i}]//*[local-name()='displayname'])" \
                - \
                <<<"$response" \
                2>/dev/null
        )"

        is_calendar="$(
            xmllint \
                --xpath \
                "count((//*[local-name()='response'])[${i}]//*[local-name()='resourcetype']/*[local-name()='calendar'])" \
                - \
                <<<"$response" \
                2>/dev/null
        )"

        is_subscribed="$(
            xmllint \
                --xpath \
                "count((//*[local-name()='response'])[${i}]//*[local-name()='resourcetype']/*[local-name()='subscribed'])" \
                - \
                <<<"$response" \
                2>/dev/null
        )"

        has_vevent="$(
            xmllint \
                --xpath \
                "count((//*[local-name()='response'])[${i}]//*[local-name()='supported-calendar-component-set']/*[local-name()='comp'][@name='VEVENT'])" \
                - \
                <<<"$response" \
                2>/dev/null
        )"

        source="$(
            xmllint \
                --xpath \
                "string((//*[local-name()='response'])[${i}]//*[local-name()='source']/*[local-name()='href'])" \
                - \
                <<<"$response" \
                2>/dev/null
        )"

        if [[ "$is_calendar" -gt 0 && "$has_vevent" -gt 0 ]]; then

            CALDAV_CALENDARS+=(
                 "calendar"$'\t'"${href}"$'\t'"${displayname}"
            )

        elif [[ "$is_subscribed" -gt 0 && -n "$source" ]]; then

            CALDAV_WEBCAL_SOURCES+=(
                "${displayname}"$'\t'"${source}"
            )

        fi

    done
    
}

caldav_collect_calendar() {

    local calendar_url="$1"

    # -------------------------------------------------------------------------
    # Build time range.
    #
    # CalDAV time-range values are expressed in UTC.
    # -------------------------------------------------------------------------

    local range_start
    local range_end

    range_start="$(date -u '+%Y%m%dT%H%M%SZ')"
    range_end="$(date -u -d 'tomorrow 23:59:59' '+%Y%m%dT%H%M%SZ')"

    # -------------------------------------------------------------------------
    # Build calendar-query REPORT.
    # -------------------------------------------------------------------------

    local report_body

    report_body="$(
        cat <<EOF
<?xml version="1.0" encoding="utf-8" ?>
<C:calendar-query
    xmlns:D="DAV:"
    xmlns:C="urn:ietf:params:xml:ns:caldav">

    <D:prop>
        <D:getetag/>
        <C:calendar-data/>
    </D:prop>

    <C:filter>
        <C:comp-filter name="VCALENDAR">
            <C:comp-filter name="VEVENT">
                <C:time-range
                    start="${range_start}"
                    end="${range_end}"/>
            </C:comp-filter>
        </C:comp-filter>
    </C:filter>

</C:calendar-query>
EOF
    )"

    # -------------------------------------------------------------------------
    # Query CalDAV server.
    # -------------------------------------------------------------------------

    local response

    response="$(
        curl -fsS \
            --max-time 15 \
            -u "${CALDAV_USERNAME}:${CALDAV_PASSWORD}" \
            -X REPORT \
            -H 'Content-Type: application/xml; charset=utf-8' \
            -H 'Depth: 1' \
            --data-binary "$report_body" \
            "${CALDAV_URL%/*}${calendar_url}"
    )" || {

        CALDAV_ERROR="Unable to query CalDAV calendar"
        return 1
    }

    # -------------------------------------------------------------------------
    # Validate XML response.
    # -------------------------------------------------------------------------

    if ! xmllint --noout - >/dev/null 2>&1 <<<"$response"; then

        CALDAV_ERROR="Invalid CalDAV XML response"
        return 1

    fi

    # -------------------------------------------------------------------------
    # Find calendar-data elements.
    # -------------------------------------------------------------------------

    local event_count

    event_count="$(
        xmllint \
            --xpath \
            'count(//*[local-name()="calendar-data"])' \
            - \
            <<<"$response" \
            2>/dev/null
    )"

    if [[ -z "$event_count" ]]; then

        CALDAV_ERROR="Unable to parse CalDAV response"
        return 1

    fi

    # -------------------------------------------------------------------------
    # Process each calendar-data block.
    # -------------------------------------------------------------------------

    local i
    local calendar_data

    for ((i = 1; i <= event_count && i <= CALDAV_MAX_EVENTS; i++)); do

        calendar_data="$(
            xmllint \
                --xpath \
                "string((//*[local-name()='calendar-data'])[${i}])" \
                - \
                <<<"$response" \
                2>/dev/null
        )"

        [[ -z "$calendar_data" ]] && continue

        caldav_parse_event "$calendar_data"

    done

}

caldav_get_calendars() {
    printf '%s\n' "${CALDAV_CALENDARS[@]}"
}

caldav_collect() {
    CALDAV_STATUS="${SW_STATUS_UNKNOWN}"
    CALDAV_ERROR=""
    CALDAV_EVENTS=()
    CALDAV_EVENT_COUNT=0
    
    # -------------------------------------------------------------------------
    # Validate configuration
    # -------------------------------------------------------------------------

    if [[ -z "$CALDAV_URL" ||
        -z "$CALDAV_USERNAME" ||
        -z "$CALDAV_PASSWORD" ]]; then

        CALDAV_ERROR="CalDAV credentials are not configured"
        return 1

    fi

    # -------------------------------------------------------------------------
    # Required commands
    # -------------------------------------------------------------------------

    if ! command -v curl >/dev/null 2>&1; then

        CALDAV_ERROR="curl is not available"
        return 1

    fi

    if ! command -v xmllint >/dev/null 2>&1; then

        CALDAV_ERROR="xmllint is not available"
        return 1

    fi

    # -------------------------------------------------------------------------
    # Discover calendars.
    # -------------------------------------------------------------------------

    local calendars

    caldav_discover_calendars || return 1

    calendars="$(caldav_get_calendars)" || return 1

    # -------------------------------------------------------------------------
    # Collect events from CalDAV calendars.
    # -------------------------------------------------------------------------

    local type
    local href
    local displayname

    while IFS=$'\t' read -r type href displayname; do

        [[ "$type" == "calendar" ]] || continue

        caldav_collect_calendar "$href" || return 1

    done <<<"$calendars"

    CALDAV_EVENT_COUNT="${#CALDAV_EVENTS[@]}"
    CALDAV_STATUS="${SW_STATUS_OK}"

    return 0

}

# -----------------------------------------------------------------------------
# Parse one iCalendar VEVENT.
# -----------------------------------------------------------------------------

caldav_parse_event() {

    local calendar_data="$1"

    local start=""
    local end=""
    local title=""
    local all_day="false"

    local line
    local unfolded=""
    local previous=""

    local start_tz=""
    local end_tz=""

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

        normalized_start="$(caldav_normalize_datetime "$start" "$start_tz")" || return
        normalized_end="$(caldav_normalize_datetime "$end" "$end_tz")" || return
    fi

    # -------------------------------------------------------------------------
    # Append normalized event.
    #
    # Format:
    #
    # start<TAB>end<TAB>title<TAB>calendar<TAB>all_day
    # -------------------------------------------------------------------------

    CALDAV_EVENTS+=(
        "${normalized_start}"$'\t'"${normalized_end}"$'\t'"${title}"$'\t'"CalDAV"$'\t'"${all_day}"
    )

}

# -----------------------------------------------------------------------------
# Normalize CalDAV date/time.
# -----------------------------------------------------------------------------

caldav_normalize_datetime() {

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
