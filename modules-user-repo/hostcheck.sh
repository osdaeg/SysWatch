#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# URL connectivity module
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="HOSTS Check"
readonly MODULE_DESCRIPTION="Check network connectivity to configured hosts"
readonly MODULE_VERSION="0.1.0"

MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-100}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly URLCHECK_PACKETS="${URLCHECK_PACKETS:-4}"
readonly URLCHECK_TIMEOUT="${URLCHECK_TIMEOUT:-2}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

declare -a URLCHECK_NAMES
declare -a URLCHECK_HOSTS
declare -a URLCHECK_RECEIVED
declare -a URLCHECK_COLORS

URLCHECK_COUNT=0
URLCHECK_STATUS="${SW_STATUS_UNKNOWN}"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

urlcheck_collect() {

    URLCHECK_NAMES=()
    URLCHECK_HOSTS=()
    URLCHECK_RECEIVED=()
    URLCHECK_COLORS=()

    URLCHECK_COUNT=0

    [[ -f "${CONFIG_DIR}/hostcheck.conf" ]] || return 0

    while IFS='=' read -r name host; do

        # Ignore empty lines and comments.
        [[ -z "$name" || "$name" == \#* ]] && continue

        # Ignore malformed entries.
        [[ -z "$host" ]] && continue

        # Remove leading/trailing whitespace.
        name="${name#"${name%%[![:space:]]*}"}"
        name="${name%"${name##*[![:space:]]}"}"

        host="${host#"${host%%[![:space:]]*}"}"
        host="${host%"${host##*[![:space:]]}"}"

        [[ -z "$name" || -z "$host" ]] && continue

        URLCHECK_NAMES+=("$name")
        URLCHECK_HOSTS+=("$host")

        output="$(
            ping \
                -c "$URLCHECK_PACKETS" \
                -W "$URLCHECK_TIMEOUT" \
                "$host" 2>/dev/null
        )"

        received="$(
            printf '%s\n' "$output" |
                sed -n 's/^[^0-9]*\([0-9][0-9]*\) packets received.*/\1/p' |
                tail -n 1
        )"

        # Some ping implementations use "received" without "packets".
        if [[ -z "$received" ]]; then
            received="$(
                printf '%s\n' "$output" |
                    sed -n 's/.*,\s*\([0-9][0-9]*\) received,.*/\1/p' |
                    tail -n 1
            )"
        fi

        received="${received:-0}"

        URLCHECK_RECEIVED+=("$received")

        ((URLCHECK_COUNT++))

    done < "${CONFIG_DIR}/hostcheck.conf"

}

urlcheck_analyze() {

    URLCHECK_STATUS="${SW_STATUS_INFO}"

    for ((i = 0; i < URLCHECK_COUNT; i++)); do

        received="${URLCHECK_RECEIVED[$i]}"

        if (( received >= URLCHECK_PACKETS )); then

            URLCHECK_COLORS+=("green")

        elif (( received * 4 >= URLCHECK_PACKETS * 3 )); then

            URLCHECK_COLORS+=("yellow")

        elif (( received * 2 >= URLCHECK_PACKETS )); then

            URLCHECK_COLORS+=("orange")

        else

            URLCHECK_COLORS+=("red")

        fi

    done

}

urlcheck_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata (consumed by lib/html.sh)
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "$(sw_translate "Hosts Check")"
    sw_state_set "module.icon" "lucide/globe"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Data
    # -------------------------------------------------------------------------

    for ((i = 0; i < URLCHECK_COUNT; i++)); do

        number=$((i + 1))

        sw_state_set \
            "url${number}" \
            "${URLCHECK_RECEIVED[$i]}/${URLCHECK_PACKETS}"

        sw_state_set \
            "url${number}.label" \
            "${URLCHECK_NAMES[$i]}"

        sw_state_set \
            "url${number}.color" \
            "${URLCHECK_COLORS[$i]}"

        sw_state_set \
            "url${number}.order" \
            "$((number * 10))"

    done

}

urlcheck_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Checked ${URLCHECK_COUNT} host(s)"

}

sw_module_run() {

    sw_state_use "urlcheck"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    urlcheck_collect

    urlcheck_analyze

    sw_status_update "${URLCHECK_STATUS}" || return 1

    urlcheck_update_state

    sw_state_save

    urlcheck_report

}