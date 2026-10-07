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

gcal_get_access_token() {

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

        GCAL_ERROR="$(
            jq -r '.error_description // .error // "Unable to obtain access token"' \
                <<<"$response"
        )"

        return 1
    fi

    printf '%s\n' "$access_token"
}

gcal_sync_calendars() {

    local access_token="$1"
    local config_file="${CONFIG_DIR}/gcal.conf"
    local response
    local tmp_file
    local calendar_id
    local calendar_name
    local enabled

    response="$(
        curl -fsS \
            --max-time 15 \
            -G \
            "https://www.googleapis.com/calendar/v3/users/me/calendarList" \
            -H "Authorization: Bearer ${access_token}" \
            -H "Accept: application/json"
    )" || return 1

    if ! jq -e '.items' >/dev/null 2>&1 <<<"$response"; then
        return 1
    fi

    mkdir -p "${CONFIG_DIR}" || return 1

    tmp_file="$(mktemp)" || return 1

    while IFS=$'\t' read -r calendar_id calendar_name; do

        [[ -n "$calendar_id" ]] || continue

        enabled="true"

        if [[ -f "$config_file" ]]; then

            enabled="$(
                awk \
                    -F= \
                    -v id="$calendar_id" \
                    '$1 == id {
                        print $2
                        found=1
                        exit
                    }
                    END {
                        if (!found)
                            exit 1
                    }' \
                    "$config_file"
            )" || enabled="true"

        fi

        printf '# %s\n' "$calendar_name" >>"$tmp_file"
        printf '%s=%s\n\n' "$calendar_id" "$enabled" >>"$tmp_file"

    done < <(
        jq -r '
            .items[] |
            [
                .id,
                (.summary // .summaryOverride // "(No title)")
            ] |
            @tsv
        ' <<<"$response"
    )

    # Keep calendars that are already configured but are no longer returned
    # by Google.
    if [[ -f "$config_file" ]]; then

        while IFS= read -r line; do

            [[ -n "$line" ]] || continue
            [[ "$line" == \#* ]] && continue

            IFS='=' read -r calendar_id enabled <<<"$line"

            calendar_id="${line%%=*}"

            if ! awk \
                -F= \
                -v id="$calendar_id" \
                '$1 == id {
                    found=1
                    exit
                }
                END {
                    exit !found
                }' \
                "$tmp_file"; then

                # Preserve the existing entry and its comment.
                previous_comment="$(
                    awk \
                        -v id="$calendar_id" '
                            found && /^#/ {
                                print
                                exit
                            }
                            $0 ~ "^" id "=" {
                                found=1
                            }
                        ' \
                        "$config_file"
                )"

                [[ -n "$previous_comment" ]] &&
                    printf '%s\n' "$previous_comment" >>"$tmp_file"

                printf '%s\n\n' "$line" >>"$tmp_file"

            fi

        done <"$config_file"

    fi

    mv "$tmp_file" "$config_file" || {
        rm -f "$tmp_file"
        return 1
    }

    return 0
}

gcal_get_enabled_calendars() {

    local config_file="${CONFIG_DIR}/gcal.conf"
    local line
    local calendar_id
    local enabled

    [[ -f "$config_file" ]] || return 1

    while IFS= read -r line; do

        # Ignore empty lines.
        [[ -n "$line" ]] || continue

        # Ignore comments. A comment starts with "# " so that calendar IDs
        # beginning with "#" remain valid.
        [[ "$line" == "# "* ]] && continue

        IFS='=' read -r calendar_id enabled <<<"$line"

        [[ -n "$calendar_id" ]] || continue
        [[ "$enabled" == "true" ]] || continue

        printf '%s\n' "$calendar_id"

    done <"$config_file"

    return 0
}

gcal_collect_events() {

    local access_token="$1"
    local calendar_id="$2"

    local time_min
    local time_max
    local calendar_response

    # -------------------------------------------------------------------------
    # Validate arguments
    # -------------------------------------------------------------------------

    [[ -n "$access_token" ]] || return 1
    [[ -n "$calendar_id" ]] || return 1

    # -------------------------------------------------------------------------
    # Build time range.
    # -------------------------------------------------------------------------

    time_min="$(date --iso-8601=seconds)"
    time_max="$(date -d 'tomorrow 23:59:59' --iso-8601=seconds)"

    # -------------------------------------------------------------------------
    # Query Google Calendar
    # -------------------------------------------------------------------------

    local encoded_calendar_id

    encoded_calendar_id="$(
        jq -rn --arg value "$calendar_id" '$value | @uri'
    )"

    calendar_response="$(
        curl -fsS \
            --max-time 15 \
            -G \
            "https://www.googleapis.com/calendar/v3/calendars/${encoded_calendar_id}/events" \
            -H "Authorization: Bearer ${access_token}" \
            --data-urlencode "timeMin=${time_min}" \
            --data-urlencode "timeMax=${time_max}" \
            --data-urlencode "maxResults=${GCAL_MAX_EVENTS}" \
            --data-urlencode "singleEvents=true" \
            --data-urlencode "orderBy=startTime"
    )" || return 1

    # -------------------------------------------------------------------------
    # Validate API response.
    # -------------------------------------------------------------------------

    if ! jq -e '.items' >/dev/null 2>&1 <<<"$calendar_response"; then
        return 1
    fi

    # -------------------------------------------------------------------------
    # Normalize events.
    #
    # Format:
    #
    #   timestamp<TAB>end_timestamp<TAB>title<TAB>calendar<TAB>all_day
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

    return 0
}

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

    local access_token

    access_token="$(gcal_get_access_token)" || return 1

    # -------------------------------------------------------------------------
    # Synchronize calendar configuration
    # -------------------------------------------------------------------------

    gcal_sync_calendars "$access_token" || {

        GCAL_ERROR="Unable to synchronize Google Calendar configuration"
        return 1
    }

    # -------------------------------------------------------------------------
    # Collect events from enabled calendars.
    # -------------------------------------------------------------------------

    local calendar_id

    while IFS= read -r calendar_id; do

        [[ -n "$calendar_id" ]] || continue

        gcal_collect_events "$access_token" "$calendar_id" || {

            GCAL_ERROR="Unable to query Google Calendar"
            return 1
        }

    done < <(gcal_get_enabled_calendars)

    # -------------------------------------------------------------------------
    # Update module state.
    # -------------------------------------------------------------------------

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
