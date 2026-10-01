#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Google Calendar module
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly GCAL_CLIENT_ID="${GCAL_CLIENT_ID:-}"
readonly GCAL_CLIENT_SECRET="${GCAL_CLIENT_SECRET:-}"
readonly GCAL_TOKEN="${GCAL_TOKEN:-}"

readonly GCAL_MAX_EVENTS="${GCAL_MAX_EVENTS:-10}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

GCAL_STATUS="${SW_STATUS_UNKNOWN}"
GCAL_EVENTS=()
GCAL_EVENT_COUNT=0
GCAL_ERROR=""

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

gcal_collect() {

    GCAL_STATUS="${SW_STATUS_UNKNOWN}"
    GCAL_ERROR=""
    GCAL_EVENTS=()
    GCAL_EVENT_COUNT=0

    # -------------------------------------------------------------------------
    # Validate configuration
    # -------------------------------------------------------------------------

    if [[ -z "$GCAL_CLIENT_ID" ||
        -z "$GCAL_CLIENT_SECRET" ||
        -z "$GCAL_TOKEN" ]]; then

        GCAL_ERROR="Google Calendar credentials are not configured"
        return 1

    fi

    # -------------------------------------------------------------------------
    # Obtain a fresh access token
    # -------------------------------------------------------------------------

    local response
    local access_token

    response="$(
        curl -fsS \
            --max-time 15 \
            -X POST \
            "https://oauth2.googleapis.com/token" \
            -d "client_id=${GCAL_CLIENT_ID}" \
            -d "client_secret=${GCAL_CLIENT_SECRET}" \
            -d "refresh_token=${GCAL_TOKEN}" \
            -d "grant_type=refresh_token"
    )" || {

        GCAL_ERROR="Unable to contact Google OAuth service"
        return 1
    }

    access_token="$(jq -r '.access_token // empty' <<<"$response")"

    if [[ -z "$access_token" ]]; then

        GCAL_ERROR="$(jq -r '.error_description // .error // "Unable to obtain access token"' <<<"$response")"
        return 1

    fi

    # -------------------------------------------------------------------------
    # Build time range.
    #
    # date uses the system timezone. The resulting ISO 8601 offsets are
    # accepted directly by Google Calendar.
    # -------------------------------------------------------------------------

    local time_min
    local time_max

    time_min="$(date --iso-8601=seconds)"
    time_max="$(date -d 'tomorrow 23:59:59' --iso-8601=seconds)"

    # -------------------------------------------------------------------------
    # Query Google Calendar
    # -------------------------------------------------------------------------

    local calendar_response

    calendar_response="$(
        curl -fsS \
            --max-time 15 \
            -G \
            "https://www.googleapis.com/calendar/v3/calendars/primary/events" \
            -H "Authorization: Bearer ${access_token}" \
            --data-urlencode "timeMin=${time_min}" \
            --data-urlencode "timeMax=${time_max}" \
            --data-urlencode "maxResults=${GCAL_MAX_EVENTS}" \
            --data-urlencode "singleEvents=true" \
            --data-urlencode "orderBy=startTime"
    )" || {

        GCAL_ERROR="Unable to query Google Calendar"
        return 1
    }

    # -------------------------------------------------------------------------
    # Check API response.
    # -------------------------------------------------------------------------

    if ! jq -e '.items' >/dev/null 2>&1 <<<"$calendar_response"; then

        GCAL_ERROR="$(jq -r '.error.message // "Invalid Google Calendar response"' <<<"$calendar_response")"
        return 1

    fi

    # -------------------------------------------------------------------------
    # Normalize events.
    #
    # Format:
    #
    #   timestamp<TAB>end_timestamp<TAB>title<TAB>calendar<TAB>all_day
    #
    # Calendar/backend information is kept internally so another backend can
    # later feed the same presentation layer.
    # -------------------------------------------------------------------------

    while IFS=$'\t' read -r start end title calendar all_day; do

        GCAL_EVENTS+=(
            "${start}"$'\t'"${end}"$'\t'"${title}"$'\t'"${calendar}"$'\t'"${all_day}"
        )

    done < <(
        jq -r '
            .items[] |
            (
                .start.dateTime //
                .start.date //
                ""
            ) as $start |
            (
                .end.dateTime //
                .end.date //
                ""
            ) as $end |
            [
                $start,
                $end,
                (.summary // "(No title)"),
                (.organizer.displayName // "Google Calendar"),
                (if .start.date then "true" else "false" end)
            ] |
            @tsv
        ' <<<"$calendar_response"
    )

    GCAL_EVENT_COUNT="${#GCAL_EVENTS[@]}"
    GCAL_STATUS="${SW_STATUS_OK}"

    return 0
}

gcal_analyze() {

    GCAL_STATUS="${SW_STATUS_OK}"

    # No events: the calendar was queried successfully.
    if ((GCAL_EVENT_COUNT == 0)); then
        return
    fi

    local first_event
    local start
    local end
    local title
    local calendar
    local all_day

    first_event="${GCAL_EVENTS[0]}"

    IFS=$'\t' read -r start end title calendar all_day <<<"$first_event"

    # All-day events do not have a meaningful "minutes until" value.
    if [[ "$all_day" == "true" ]]; then
        return
    fi

    local start_timestamp
    local now_timestamp
    local seconds_until
    local minutes_until

    start_timestamp="$(date -d "$start" +%s 2>/dev/null)" || return
    now_timestamp="$(date +%s)"

    seconds_until=$((start_timestamp - now_timestamp))
    minutes_until=$((seconds_until / 60))

    if ((seconds_until <= 0)); then

        GCAL_STATUS="${SW_STATUS_CRITICAL}"

    elif ((minutes_until <= 10)); then

        GCAL_STATUS="${SW_STATUS_CRITICAL}"

    elif ((minutes_until <= 30)); then

        GCAL_STATUS="${SW_STATUS_WARNING}"

    elif ((minutes_until <= 120)); then

        GCAL_STATUS="${SW_STATUS_INFO}"

    fi

}

