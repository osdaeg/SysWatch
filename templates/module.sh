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

readonly MODULE_NAME="Example"
readonly MODULE_DESCRIPTION="Example module description"
readonly MODULE_VERSION="0.1.0"

MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-10}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly EXAMPLE_WARNING="${EXAMPLE_WARNING:-80}"
readonly EXAMPLE_CRITICAL="${EXAMPLE_CRITICAL:-95}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

EXAMPLE_VALUE=0
EXAMPLE_STATUS="${SW_STATUS_UNKNOWN}"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

example_collect() {

    # Collect raw metrics here.
    # This step should not determine the module status.

    EXAMPLE_VALUE=0

}

example_analyze() {

    EXAMPLE_STATUS="${SW_STATUS_OK}"

    if (( EXAMPLE_VALUE >= EXAMPLE_CRITICAL )); then

        EXAMPLE_STATUS="${SW_STATUS_CRITICAL}"

    elif (( EXAMPLE_VALUE >= EXAMPLE_WARNING )); then

        EXAMPLE_STATUS="${SW_STATUS_WARNING}"

    fi

}

example_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata (consumed by lib/html.sh)
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "Example"
    sw_state_set "module.icon" "lucide/box"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Data
    # -------------------------------------------------------------------------

    sw_state_set "value" "${EXAMPLE_VALUE}"

    sw_state_set "value.label" "Value"
    sw_state_set "value.widget" "line"
    sw_state_set "value.unit" ""
    sw_state_set "value.order" "10"
    sw_state_set "value.warning" "${EXAMPLE_WARNING}"
    sw_state_set "value.critical" "${EXAMPLE_CRITICAL}"

}

example_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Example value: ${EXAMPLE_VALUE} (${EXAMPLE_STATUS})"

}

sw_module_run() {

    sw_state_use "example"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    example_collect

    example_analyze

    sw_status_update "${EXAMPLE_STATUS}" || return 1

    example_update_state

    sw_state_save

    example_report

    # Optional: append to CSV history for sparkline widgets.
    #
    # sw_csv_append \
    #     "example" \
    #     "value" \
    #     "${EXAMPLE_VALUE}"

}
