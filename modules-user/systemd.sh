#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Systemd failed units monitoring
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Systemd"
readonly MODULE_DESCRIPTION="Systemd failed units monitoring"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-1260}
MODULE_ORDER=${MODULE_ORDER:-51}
MODULE_REMOTE=${MODULE_REMOTE:-""}


# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------
#
# No thresholds, no sustained-samples debounce here on purpose: a failed
# unit either is or isn't failed right now, there's no "spike" to filter
# out like with CPU/disk/temperature. And unlike those, failed units are
# transient by nature (they disappear from `systemctl --failed` the moment
# they're fixed) -- so this stays a single-instance module (one state
# file) instead of one state file per unit, which would otherwise never
# get cleared back to OK once a unit recovered and vanished from the list.
#

SYSTEMD_STATE=""
SYSTEMD_FAILED_UNITS=()
SYSTEMD_STATUS="${SW_STATUS_OK}"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

systemd_collect() {

    SYSTEMD_STATE="$(systemctl is-system-running 2>/dev/null)" || true

    SYSTEMD_FAILED_UNITS=()

    while read -r unit
    do

        [[ -n "${unit}" ]] && SYSTEMD_FAILED_UNITS+=("${unit}")

    done < <(
        systemctl --failed --plain --no-legend 2>/dev/null |
        awk '{ print $1 }'
    )

}

systemd_analyze() {

    SYSTEMD_STATUS="${SW_STATUS_OK}"

    if (( ${#SYSTEMD_FAILED_UNITS[@]} > 0 )); then

        SYSTEMD_STATUS="${SW_STATUS_CRITICAL}"

    elif [[ "${SYSTEMD_STATE}" == "degraded" || "${SYSTEMD_STATE}" == "maintenance" ]]; then

        SYSTEMD_STATUS="${SW_STATUS_WARNING}"

    fi

}

systemd_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.label" "Systemd"
    sw_state_set "module.icon" "lucide/server"
    sw_state_set "module.order" "$MODULE_ORDER"

    sw_state_set "system_state" "${SYSTEMD_STATE}"
    sw_state_set "system_state.label" "Estado"

    sw_state_set "failed_count" "${#SYSTEMD_FAILED_UNITS[@]}"
    sw_state_set "failed_count.label" "Unidades fallidas"

    local units_joined=""

    if (( ${#SYSTEMD_FAILED_UNITS[@]} > 0 )); then

        units_joined="$(IFS=', '; printf '%s' "${SYSTEMD_FAILED_UNITS[*]}")"

    fi

    sw_state_set "failed_units" "${units_joined}"
    sw_state_set "failed_units.label" "Detalle"

    # Only shown when there's actually something to show -- an empty text
    # field would otherwise just render as a blank row.
    if [[ -z "${units_joined}" ]]; then

        sw_state_set "failed_units.hidden" "true"

    fi

}

systemd_report() {

    if (( ${#SYSTEMD_FAILED_UNITS[@]} > 0 )); then

        sw_log_info \
            "${MODULE_NAME}" \
            "Systemd: ${#SYSTEMD_FAILED_UNITS[@]} failed unit(s): ${SYSTEMD_FAILED_UNITS[*]}"

    else

        sw_log_info \
            "${MODULE_NAME}" \
            "Systemd: no failed units (state: ${SYSTEMD_STATE})"

    fi

}

sw_module_run() {

    sw_require_command systemctl || return 127

    sw_state_use "systemd"
    sw_state_load

    systemd_collect

    systemd_analyze

    sw_status_update "${SYSTEMD_STATUS}" || return 1

    systemd_update_state

    sw_state_save

    systemd_report

}
