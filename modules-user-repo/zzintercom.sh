#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Intercom: read every .message file in cache directory and create a card
#
# Copy this file into modules-user/ or modules-root/, rename it, and replace
# every "INTERCOM"/"intercom" placeholder with your module's name.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="InterCom"
readonly MODULE_SCRIPT="$(realpath "${BASH_SOURCE[0]}")"
readonly MODULE_DESCRIPTION="Show .message files stored in cache directory"
readonly MODULE_VERSION="0.1.0"

MODULE_INTERVAL=${MODULE_INTERVAL:-240}
MODULE_INTERVAL_NORMAL=${MODULE_INTERVAL_NORMAL:-}
MODULE_INTERVAL_ALT=${MODULE_INTERVAL_ALT:-}

MODULE_ORDER=${MODULE_ORDER:-10}

MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly INTERCOM_WARNING="${INTERCOM_WARNING:-80}"
readonly INTERCOM_CRITICAL="${INTERCOM_CRITICAL:-95}"
# and any other necessary variable...

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

INTERCOM_VALUE=0
INTERCOM_STATUS="${SW_STATUS_UNKNOWN}"
# and any other necessary variable...

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

intercom_collect() {

    # Collect raw metrics here.
    # This step should not determine the module status.

    INTERCOM_VALUE=0

}

intercom_analyze() {

    # Regardless of the visual configuration of the widgets, the module status is generally
    # determined by analyzing the collected values and changing the *_STATUS variable.

    INTERCOM_STATUS="${SW_STATUS_INFO}"

}

intercom_update_state() {

    local order=1
    local localhostname
    localhostname=$(hostname)

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.label" "$(sw_translate "InterCom")"
    sw_state_set "module.icon" "lucide/message-square-text"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Data
    # -------------------------------------------------------------------------

    # El if verifica si el primer archivo que coincide con la expansión realmente existe
    if compgen -G "$CACHE_DIR/*.message" >/dev/null; then
        for archivo in "$CACHE_DIR"/*.message; do

            local message_hostname=""
            local sender=""
            local message_date=""
            local message=""
            local line
            local key
            local value

            while IFS= read -r line || [[ -n "$line" ]]; do
                key="${line%%=*}"
                value="${line#*=}"

                case "$key" in
                hostname | sender | date | message)
                    value="$(printf '%s' "$value" | base64 -d)" || continue
                    case "$key" in
                    hostname) message_hostname="$value" ;;
                    sender) sender="$value" ;;
                    date) message_date="$value" ;;
                    message) message="$value" ;;
                    esac
                    ;;
                esac
            done <"$archivo"

            [[ "$message_hostname" = "$localhostname" ]] && message_hostname=""

            #sw_state_set "value${order}" "$(printf "$(sw_translate "From: %s<br>Date: %s<br>Message: %s<br>Host: %s<br>")\n" \
            #    "$sender" "$message_date" "$message" "$message_hostname")"

            local card

            local from_label
            local date_label
            local message_label
            local host_label

            from_label="$(sw_translate "From:")"
            date_label="$(sw_translate "Date:")"
            message_label="$(sw_translate "Message:")"
            host_label="$(sw_translate "Host:")"

            card="$(printf '<span style="color: skyblue"><i>%s</i></span> %s<br><span style="color: skyblue"><i>%s</i></span> %s<br><span style="color: skyblue"><i>%s</i></span> %s<br><span style="color: skyblue"><i>%s</i></span> %s' \
                "$from_label" "$sender" \
                "$date_label" "$message_date" \
                "$message_label" "$message" \
                "$host_label" "$message_hostname")"

            sw_state_set "value${order}" "$card"

            sw_state_set "value${order}.order" "$order"
            sw_state_set "value${order}.label" "$order"
            sw_state_set "value${order}.align" "left"

            ((order++))

            mv "$archivo" "${CACHE_DIR}/archive" || return 1
        done

        sw_status_update "${INTERCOM_STATUS}" || return 1

        sw_state_save
    else
        INTERCOM_STATUS="${SW_STATUS_OK}"
        echo "InterCom borró el state"
        sw_state_delete
    fi

}

intercom_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Intercom value: ${INTERCOM_VALUE} (${INTERCOM_STATUS})"

}

sw_module_run() {

    sw_state_use "intercom"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_mkdir "${CACHE_DIR}/archive"

    sw_state_load

    sw_state_clear

    # intercom_collect

    intercom_analyze

    intercom_update_state

    intercom_report

}
