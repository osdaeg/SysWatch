#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Zombie processes module
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Zombies"
readonly MODULE_DESCRIPTION="Zombie process detection"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-1000}
MODULE_REMOTE=${MODULE_REMOTE:-""}


# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

ZOMBIE_COUNT=0
ZOMBIE_STATUS="${SW_STATUS_UNKNOWN}"
ZOMBIE_DETAILS=""


# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

zombie_collect() {

    ZOMBIE_COUNT=0
    ZOMBIE_DETAILS=""

    while read -r pid ppid stat comm; do

        ((ZOMBIE_COUNT++))

        parent_comm=$(ps -p "$ppid" -o comm= 2>/dev/null)

        [[ -z "$parent_comm" ]] && parent_comm="?"

        ZOMBIE_DETAILS+="PID ${pid}: ${comm}<br>"
        ZOMBIE_DETAILS+="Padre: ${ppid} ${parent_comm}<br>"

    done < <(
        ps -eo pid=,ppid=,stat=,comm= |
        awk '$3 ~ /^Z/ { print $1, $2, $3, $4 }'
    )

}


zombie_analyze() {

    ZOMBIE_STATUS="${SW_STATUS_OK}"

    if (( ZOMBIE_COUNT > 0 )); then

        ZOMBIE_STATUS="${SW_STATUS_CRITICAL}"

    fi

}


zombie_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "Zombies"
    sw_state_set "module.icon" "icojam/zombie"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Data
    # -------------------------------------------------------------------------

    sw_state_set "count" "${ZOMBIE_COUNT}"

    sw_state_set "count.label" "Procesos zombie"
    sw_state_set "count.widget" "value"
    sw_state_set "count.unit" ""
    sw_state_set "count.order" "10"

    if (( ZOMBIE_COUNT > 0 )); then

        sw_state_set "details" "${ZOMBIE_DETAILS}"
        sw_state_set "details.label" "Procesos"
        sw_state_set "details.widget" "message"
        sw_state_set "details.order" "20"

    else    
        sw_state_set "details" "ninguno"
        sw_state_set "details.label" "Procesos"
        sw_state_set "details.widget" "message"
        sw_state_set "details.order" "20"
    fi

}


zombie_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Zombie processes: ${ZOMBIE_COUNT} (${ZOMBIE_STATUS})"

}


sw_module_run() {

    sw_state_use "zombies"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    zombie_collect

    zombie_analyze

    sw_status_update "${ZOMBIE_STATUS}" || return 1

    zombie_update_state

    sw_state_save

    zombie_report

}