#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# gpu module
#
# Reports GPU voltage and clock information.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="GPU"
readonly MODULE_DESCRIPTION="GPU hardware sensors"
readonly MODULE_VERSION="0.1.0"

MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-1170}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

GPU_STATUS="${SW_STATUS_UNKNOWN}"

GPU_AVAILABLE=false

GPU_VDDGFX=""
GPU_VDDNB=""
GPU_SCLK=""

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

gpu_collect() {

    GPU_STATUS="${SW_STATUS_UNKNOWN}"

    GPU_AVAILABLE=false

    GPU_VDDGFX=""
    GPU_VDDNB=""
    GPU_SCLK=""

    command -v sensors >/dev/null 2>&1 || return 0

    local output

    output="$(sensors 2>/dev/null)" || return 0

    [[ -n "$output" ]] || return 0

    local line

    while IFS= read -r line; do

        # ---------------------------------------------------------------------
        # GPU core voltage
        # ---------------------------------------------------------------------

        if [[ "$line" =~ ^vddgfx:[[:space:]]*([0-9.]+)[[:space:]]*mV ]]; then

            GPU_VDDGFX="${BASH_REMATCH[1]}"
            GPU_AVAILABLE=true

            continue

        fi

        # ---------------------------------------------------------------------
        # GPU Northbridge voltage
        # ---------------------------------------------------------------------

        if [[ "$line" =~ ^vddnb:[[:space:]]*([0-9.]+)[[:space:]]*V ]]; then

            GPU_VDDNB="${BASH_REMATCH[1]}"
            GPU_AVAILABLE=true

            continue

        fi

        # ---------------------------------------------------------------------
        # GPU clock
        # ---------------------------------------------------------------------

        if [[ "$line" =~ ^sclk:[[:space:]]*([0-9]+)[[:space:]]*MHz ]]; then

            GPU_SCLK="${BASH_REMATCH[1]}"
            GPU_AVAILABLE=true

            continue

        fi

    done <<<"$output"

}

gpu_analyze() {

    if [[ "$GPU_AVAILABLE" != true ]]; then

        GPU_STATUS="${SW_STATUS_UNKNOWN}"

        return

    fi

    GPU_STATUS="${SW_STATUS_OK}"

}

gpu_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "$(sw_translate "GPU")"
    sw_state_set "module.icon" "lucide/gpu"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Availability
    # -------------------------------------------------------------------------

    sw_state_set "available" "${GPU_AVAILABLE}"

    # -------------------------------------------------------------------------
    # GPU core voltage
    # -------------------------------------------------------------------------

    if [[ -n "$GPU_VDDGFX" ]]; then

        sw_state_set "vddgfx" "${GPU_VDDGFX}"
        sw_state_set "vddgfx.label" "$(sw_translate "GPU voltage")"
        sw_state_set "vddgfx.widget" "value"
        sw_state_set "vddgfx.unit" "mV"
        sw_state_set "vddgfx.order" "10"

    fi

    # -------------------------------------------------------------------------
    # GPU Northbridge voltage
    # -------------------------------------------------------------------------

    if [[ -n "$GPU_VDDNB" ]]; then

        sw_state_set "vddnb" "${GPU_VDDNB}"
        sw_state_set "vddnb.label" "$(sw_translate "GPU NB voltage")"
        sw_state_set "vddnb.widget" "value"
        sw_state_set "vddnb.unit" "V"
        sw_state_set "vddnb.order" "20"

    fi

    # -------------------------------------------------------------------------
    # GPU clock
    # -------------------------------------------------------------------------

    if [[ -n "$GPU_SCLK" ]]; then

        sw_state_set "sclk" "${GPU_SCLK}"
        sw_state_set "sclk.label" "$(sw_translate "GPU clock")"
        #sw_state_set "sclk.widget" "line"
        sw_state_set "sclk.unit" "MHz"
        sw_state_set "sclk.order" "30"
        sw_state_set "sclk.color" "yellow"

    fi

}

gpu_report() {

    if [[ "$GPU_AVAILABLE" != true ]]; then

        sw_log_info \
            "${MODULE_NAME}" \
            "GPU sensors unavailable"

        return

    fi

    local message="GPU"

    [[ -n "$GPU_VDDGFX" ]] &&
        message+=" | Voltage: ${GPU_VDDGFX} mV"

    [[ -n "$GPU_VDDNB" ]] &&
        message+=" | NB: ${GPU_VDDNB} V"

    [[ -n "$GPU_SCLK" ]] &&
        message+=" | Clock: ${GPU_SCLK} MHz"

    sw_log_info \
        "${MODULE_NAME}" \
        "${message} (${GPU_STATUS})"

}

# -----------------------------------------------------------------------------
# Module entry point
# -----------------------------------------------------------------------------

sw_module_run() {

    sw_state_use "gpu"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    gpu_collect

    gpu_analyze

    sw_status_update "${GPU_STATUS}" || return 1

    gpu_update_state

    sw_state_save

    # -------------------------------------------------------------------------
    # CSV history
    # -------------------------------------------------------------------------

    if [[ -n "$GPU_SCLK" ]]; then

        sw_csv_append \
            "gpu" \
            "sclk" \
            "${GPU_SCLK}"

    fi

    gpu_report

}
