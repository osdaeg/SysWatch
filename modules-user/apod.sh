#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# module template
#
# Copy this file into modules-user/ or modules-root/, rename it, and replace
# every "EXAMPLE"/"example" placeholder with your module's name.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="APOD"
readonly MODULE_DESCRIPTION="Show APOD"
readonly MODULE_VERSION="0.1.0"
readonly MODULE_INTERVAL=43200

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly APOD_WARNING="${APOD_WARNING:-80}"
readonly APOD_CRITICAL="${APOD_CRITICAL:-95}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

APOD_NAME=""
APOD_EXT=""
APOD_STATUS="${SW_STATUS_UNKNOWN}"
APOD_PATH="/home/daniel/docker/webserver/sites/apod/images"
APOD_VALUE=0

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

apod_collect() {

    # Collect raw metrics here.
    # This step should not determine the module status.

    APOD_LAST=$(find "${APOD_PATH}" -maxdepth 1 -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    APOD_NAME=$(basename ${APOD_LAST})
    APOD_EXT="${APOD_NAME##*.}"
    mkdir -p "${HTML_DIR}/images"
    cp "${APOD_PATH}/${APOD_NAME}" "${HTML_DIR}/images/foto.${APOD_EXT}"


}

apod_analyze() {

    APOD_STATUS="${SW_STATUS_OK}"

    if (( APOD_VALUE >= APOD_CRITICAL )); then

        APOD_STATUS="${SW_STATUS_CRITICAL}"

    elif (( APOD_VALUE >= APOD_WARNING )); then

        APOD_STATUS="${SW_STATUS_WARNING}"

    fi

}

apod_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata (consumed by lib/html.sh)
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "APOD"
    sw_state_set "module.icon" "lucide/telescope"
    sw_state_set "module.order" "800"

    # -------------------------------------------------------------------------
    # Data
    # -------------------------------------------------------------------------

    sw_state_set "image" "foto.${APOD_EXT}"

    sw_state_set "image.label" "Foto del día"
    sw_state_set "image.widget" "image"
    sw_state_set "image.unit" ""
    sw_state_set "image.order" "10"
    sw_state_set "image.warning" "${APOD_WARNING}"
    sw_state_set "image.critical" "${APOD_CRITICAL}"

}

apod_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "APOD value: ${APOD_NAME} (${APOD_STATUS})"

}

sw_module_run() {

    sw_state_use "apod"
    sw_state_load

    apod_collect

    apod_analyze

    sw_status_update "${APOD_STATUS}" || return 1

    apod_update_state

    sw_state_save

    apod_report

    # Optional: append to CSV history for sparkline widgets.
    #
    # sw_csv_append \
    #     "example" \
    #     "value" \
    #     "${APOD_VALUE}"

}
