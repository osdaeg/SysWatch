#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Privilege monitoring module
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Privileges"
readonly MODULE_DESCRIPTION="Execution privilege verification"
readonly MODULE_VERSION="0.1.0"
readonly MODULE_INTERVAL=3600

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

PRIVILEGES_UID=0
PRIVILEGES_USER=""
PRIVILEGES_EUID=0

PRIVILEGES_STATUS="UNKNOWN"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

collect() {

    PRIVILEGES_UID="$(id -u)"
    PRIVILEGES_EUID="${EUID}"
    PRIVILEGES_USER="$(id -un)"

}

analyze() {

    PRIVILEGES_STATUS="OK"

    if (( PRIVILEGES_EUID != 0 )); then

        PRIVILEGES_STATUS="CRITICAL"

    fi

}

update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "uid" "${PRIVILEGES_UID}"
    sw_state_set "euid" "${PRIVILEGES_EUID}"
    sw_state_set "user" "${PRIVILEGES_USER}"

    sw_state_set "module.label" "ROOT"
    sw_state_set "module.icon" "lucide/user-lock"
    sw_state_set "module.order" "7000"
    
    
    sw_state_set "user.label"  "Usuario"
    sw_state_set "user.order" "20"
    sw_state_set "uid.label"  "ID de usuario"
    sw_state_set "uid.order" "30"
    sw_state_set "euid.label" "ID Efectivo"
    sw_state_set "euid.order" "40"
}

report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Running as ${PRIVILEGES_USER} (uid=${PRIVILEGES_UID}, euid=${PRIVILEGES_EUID}) (${PRIVILEGES_STATUS})"

}

sw_module_run() {

    sw_state_use "privileges"
    sw_state_load

    collect
    analyze

    sw_status_update "${PRIVILEGES_STATUS}"

    update_state

    sw_state_save

    report

}
