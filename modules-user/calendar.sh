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

readonly MODULE_NAME="Calendar"
readonly MODULE_DESCRIPTION="Upcoming calendar events"
readonly MODULE_VERSION="0.1.0"

MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-1050}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

source "${HELPERS_DIR}"/gcal.sh
source "${HELPERS_DIR}"/caldav.sh
source "${HELPERS_DIR}"/webcal.sh

CALENDAR_EVENTS=()
CALENDAR_EVENT_COUNT=0
CALENDAR_ERROR=""
CALENDAR_STATUS="${SW_STATUS_UNKNOWN}"

readonly CALENDAR_MAX_EVENTS="${CALENDAR_MAX_EVENTS:-10}"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

calendar_expand_all_day_events() {

    local event

    local start
    local end
    local title
    local calendar
    local all_day

    local today_date
    local tomorrow_date

    local current_date
    local next_date

    local -a expanded_events=()

    today_date="$(date +%Y-%m-%d)"
    tomorrow_date="$(date -d tomorrow +%Y-%m-%d)"

    for event in "${CALENDAR_EVENTS[@]}"; do

        IFS=$'\t' read -r \
            start \
            end \
            title \
            calendar \
            all_day <<<"$event"

        if [[ "$all_day" != "true" ]]; then

            expanded_events+=("$event")
            continue

        fi

        current_date="$start"

        while [[ "$current_date" < "$end" ]]; do

            next_date="$(date -d "$current_date + 1 day" '+%Y-%m-%d')"

            if [[ "$current_date" == "$today_date" ||
                "$current_date" == "$tomorrow_date" ]]; then

                expanded_events+=(
                    "${current_date}"$'\t'"${next_date}"$'\t'"${title}"$'\t'"${calendar}"$'\t'"true"
                )

            fi

            current_date="$next_date"

        done

    done

    CALENDAR_EVENTS=("${expanded_events[@]}")
}

calendar_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "$(sw_translate "Calendar")"
    sw_state_set "module.icon" "lucide/calendar-days"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Remove previous dynamic fields.
    # -------------------------------------------------------------------------

    local i

    for ((i = 1; i <= 100; i++)); do

        sw_state_delete_key "event_${i}"
        sw_state_delete_key "event_${i}.label"
        sw_state_delete_key "event_${i}.order"

    done

    sw_state_delete_key "today"
    sw_state_delete_key "today.label"
    sw_state_delete_key "today.order"

    sw_state_delete_key "tomorrow"
    sw_state_delete_key "tomorrow.label"
    sw_state_delete_key "tomorrow.order"

    sw_state_delete_key "next_event"
    sw_state_delete_key "next_event.label"
    sw_state_delete_key "next_event.order"

    sw_state_delete_key "next_event_time"
    sw_state_delete_key "next_event_time.label"
    sw_state_delete_key "next_event_time.order"

    sw_state_delete_key "next_event_countdown"
    sw_state_delete_key "next_event_countdown.label"
    sw_state_delete_key "next_event_countdown.order"

    sw_state_delete_key "error"
    sw_state_delete_key "error.label"
    sw_state_delete_key "error.order"

    # -------------------------------------------------------------------------
    # Error
    # -------------------------------------------------------------------------

    if [[ -n "$CALENDAR_ERROR" ]]; then

        sw_state_set "error" "${CALENDAR_ERROR}"
        sw_state_set "error.label" "$(sw_translate "Error")"
        sw_state_set "error.order" "10"

        return

    fi

    # -------------------------------------------------------------------------
    # No events
    # -------------------------------------------------------------------------

    if ((CALENDAR_EVENT_COUNT == 0)); then

        sw_state_set \
            "events" \
            "$(sw_translate "No events until tomorrow")"

        sw_state_set "events.label" "$(sw_translate "Events")"
        sw_state_set "events.order" "10"

        sw_state_delete_key "next_event"
        sw_state_delete_key "next_event.label"
        sw_state_delete_key "next_event.order"

        return

    else

        sw_state_delete_key "events"
        sw_state_delete_key "events.label"
        sw_state_delete_key "events.order"

    fi

    # -------------------------------------------------------------------------
    # Events
    # -------------------------------------------------------------------------

    local today_date
    local tomorrow_date

    today_date="$(date +%Y-%m-%d)"
    tomorrow_date="$(date -d tomorrow +%Y-%m-%d)"

    local index=1

    local today_event_order=30
    local tomorrow_event_order=300

    local start
    local end
    local title
    local calendar
    local all_day
    local event

    local event_date
    local display_time
    local display_title
    local display_event

    local has_today_events=false
    local has_tomorrow_events=false

    for event in "${CALENDAR_EVENTS[@]}"; do

        IFS=$'\t' read -r start end title calendar all_day <<<"$event"

        # ---------------------------------------------------------------------
        # Determine event date.
        # ---------------------------------------------------------------------

        if [[ "$all_day" == "true" ]]; then

            event_date="${start}"

        else

            event_date="${start:0:10}"

        fi

        echo "event: $title | start: $start | event_date: $event_date | today: $today_date | tomorrow: $tomorrow_date"

        # ---------------------------------------------------------------------
        # Create section heading only when the day has events.
        # ---------------------------------------------------------------------

        if [[ "$event_date" == "$today_date" ]]; then

            if [[ "$has_today_events" == false ]]; then

                sw_state_set \
                    "today" \
                    "$(sw_translate "Today")"

                sw_state_set \
                    "today.label" \
                    "----------"

                sw_state_set \
                    "today.order" \
                    "20"

                sw_state_set "today.color" "orange"

                has_today_events=true

            fi

            today_event_order=$((today_event_order + 10))

            sw_state_set \
                "event_${index}.order" \
                "${today_event_order}"

        elif [[ "$event_date" == "$tomorrow_date" ]]; then

            if [[ "$has_tomorrow_events" == false ]]; then

                sw_state_set \
                    "tomorrow" \
                    "$(sw_translate "Tomorrow")"

                sw_state_set \
                    "tomorrow.label" \
                    "----------"

                sw_state_set \
                    "tomorrow.order" \
                    "300"

                sw_state_set "tomorrow.color" "orange"

                has_tomorrow_events=true

            fi

            tomorrow_event_order=$((tomorrow_event_order + 10))

            sw_state_set \
                "event_${index}.order" \
                "${tomorrow_event_order}"

        fi

        # ---------------------------------------------------------------------
        # Human-readable event.
        # ---------------------------------------------------------------------

        if [[ "$all_day" == "true" ]]; then

            display_time="$(sw_translate "All day")"

        else

            display_time="$(date -d "$start" '+%H:%M')"

        fi

        display_title="${title}"

        display_event="${display_time} · ${display_title}"

        sw_state_set \
            "event_${index}" \
            "${display_event}"

        sw_state_set \
            "event_${index}.label" \
            "${index}"

        ((index++))

    done

    # -------------------------------------------------------------------------
    # Next event summary.
    #
    # The first event returned by Google is the next chronological event.
    # -------------------------------------------------------------------------

    local first_event
    local next_start
    local next_end
    local next_title
    local next_calendar
    local next_all_day

    first_event="${CALENDAR_EVENTS[0]}"

    IFS=$'\t' read -r \
        next_start \
        next_end \
        next_title \
        next_calendar \
        next_all_day <<<"$first_event"

    sw_state_set "next_header" "----------"
    sw_state_set "next_header.label" "$(sw_translate "Next event")"
    sw_state_set "next_header.order" "4"
    sw_state_set "next_header.color" "orange"

    if [[ "$next_all_day" == "true" ]]; then

        sw_state_set \
            "next_event" \
            "${next_title}"

        sw_state_set \
            "next_event.label" \
            "$(sw_translate "All day")"

        sw_state_set "next_event.order" "5"

    else

        local next_time
        local now_timestamp
        local next_timestamp
        local seconds_until
        local minutes_until
        local countdown

        next_time="$(date -d "$next_start" '+%H:%M')"

        now_timestamp="$(date +%s)"
        next_timestamp="$(date -d "$next_start" +%s)"

        seconds_until=$((next_timestamp - now_timestamp))

        if ((seconds_until <= 0)); then

            countdown="$(sw_translate "In progress")"

        else

            minutes_until=$((seconds_until / 60))

            if ((minutes_until < 1)); then

                countdown="$(sw_translate "Less than a minute")"

            elif ((minutes_until == 1)); then

                countdown="$(sw_translate "In 1 minute")"

            else

                countdown="$(printf "$(sw_translate "In %s minutes")\n" \
                    "${minutes_until}")"

            fi

        fi

        sw_state_set \
            "next_event" \
            "${next_title}"

        sw_state_set \
            "next_event.label" \
            "${next_time}"

        sw_state_set \
            "next_event.order" "5"

        sw_state_set \
            "next_event_countdown" \
            "${countdown}"

        sw_state_set \
            "next_event_countdown.label" \
            "$(sw_translate "Countdown")"

        sw_state_set \
            "next_event_countdown.order" "6"

    fi

}

calendar_sort_events() {

    local sorted

    sorted="$(
        printf '%s\n' "${CALENDAR_EVENTS[@]}" |
            awk -F '\t' '
                {
                    if ($5 == "true") {
                        order = substr($1, 1, 10) " 1 00:00:00"
                    } else {
                        order = substr($1, 1, 10) " 0 " substr($1, 12)
                    }

                    print order "\t" $0
                }
            ' |
            sort -t $'\t' -k1,1 |
            cut -f2-
    )"

    CALENDAR_EVENTS=()

    while IFS= read -r event; do
        [[ -n "$event" ]] || continue
        CALENDAR_EVENTS+=("$event")
    done <<<"$sorted"

}

calendar_report() {

    if [[ -n "$CALENDAR_ERROR" ]]; then

        sw_log_info \
            "${MODULE_NAME}" \
            "Calendar query failed: ${CALENDAR_ERROR}"

        return
    fi

    sw_log_info \
        "${MODULE_NAME}" \
        "Calendar: ${CALENDAR_EVENT_COUNT} upcoming event(s)"

}

calendar_analyze() {

    CALENDAR_STATUS="${SW_STATUS_OK}"

    local event
    local start
    local end
    local title
    local calendar
    local all_day
    local event_epoch
    local now_epoch
    local minutes

    now_epoch="$(date +%s)"

    for event in "${CALENDAR_EVENTS[@]}"; do

        IFS=$'\t' read -r start end title calendar all_day <<<"$event"

        # All-day events do not affect urgency.
        [[ "$all_day" == "true" ]] && continue

        event_epoch="$(date -d "$start" +%s 2>/dev/null)" || continue

        minutes="$(((event_epoch - now_epoch) / 60))"

        if ((minutes < 0)); then
            CALENDAR_STATUS="${SW_STATUS_CRITICAL}"
            return

        elif ((minutes <= 10)); then
            CALENDAR_STATUS="${SW_STATUS_CRITICAL}"
            return

        elif ((minutes <= 30)); then
            CALENDAR_STATUS="${SW_STATUS_WARNING}"
            return

        elif ((minutes <= 120)); then
            CALENDAR_STATUS="${SW_STATUS_INFO}"
            return

        else
            CALENDAR_STATUS="${SW_STATUS_OK}"
            return
        fi

    done
}

sw_module_run() {

    sw_state_use "calendar"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    caldav_collect
    
    webcal_collect
    
    gcal_collect

    CALENDAR_EVENTS=(
        "${GCAL_EVENTS[@]}"
        "${CALDAV_EVENTS[@]}"
        "${WEBCAL_EVENTS[@]}"
    )

    calendar_expand_all_day_events

    CALENDAR_EVENT_COUNT="${#CALENDAR_EVENTS[@]}"

    calendar_sort_events
    calendar_analyze

    sw_status_update "${CALENDAR_STATUS}" || return 1

    calendar_update_state

    sw_state_save

    calendar_report
}
