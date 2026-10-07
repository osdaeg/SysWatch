#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# sensors module
#
# Reports hardware sensors other than temperatures.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Sensors"
readonly MODULE_DESCRIPTION="Hardware sensors"
readonly MODULE_VERSION="0.1.0"

MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-1150}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly SENSORS_WARNING="${SENSORS_WARNING:-80}"
readonly SENSORS_CRITICAL="${SENSORS_CRITICAL:-95}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

SENSORS_STATUS="${SW_STATUS_UNKNOWN}"

SENSORS_AVAILABLE=false

SENSORS_POWER=""
SENSORS_POWER_AVG=""
SENSORS_POWER_CRIT=""

SENSORS_GPU_VDDGFX=""
SENSORS_GPU_VDDNB=""
SENSORS_GPU_SCLK=""

declare -a SENSORS_FANS=()
declare -a SENSORS_PWMS=()

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

sensors_collect() {

    SENSORS_STATUS="${SW_STATUS_UNKNOWN}"

    SENSORS_AVAILABLE=false

    SENSORS_POWER=""
    SENSORS_POWER_AVG=""
    SENSORS_POWER_CRIT=""

    SENSORS_GPU_VDDGFX=""
    SENSORS_GPU_VDDNB=""
    SENSORS_GPU_SCLK=""

    SENSORS_FANS=()
    SENSORS_PWMS=()

    SENSORS_FAN1=""
SENSORS_FAN2=""
SENSORS_FAN3=""

    command -v sensors >/dev/null 2>&1 || return 0

    local output

    output="$(sensors 2>/dev/null)" || return 0

    [[ -n "$output" ]] || return 0

    SENSORS_AVAILABLE=true

    local line
    local fan_name=""
    local fan_value=""
    local fan_alarm=""

    while IFS= read -r line; do

        # ---------------------------------------------------------------------
        # Fan RPM
        # ---------------------------------------------------------------------

        if [[ "$line" =~ ^(fan[0-9]+):[[:space:]]*([0-9]+)[[:space:]]*RPM(.*)$ ]]; then

        case "$fan_name" in
    fan1) SENSORS_FAN1="$fan_value" ;;
    fan2) SENSORS_FAN2="$fan_value" ;;
    fan3) SENSORS_FAN3="$fan_value" ;;
esac

            fan_name="${BASH_REMATCH[1]}"
            fan_value="${BASH_REMATCH[2]}"
            fan_alarm=""

            [[ "${BASH_REMATCH[3]}" == *"ALARM"* ]] &&
                fan_alarm="ALARM"

            SENSORS_FANS+=(
                "${fan_name}|${fan_value}|${fan_alarm}"
            )

            continue

        fi

        # ---------------------------------------------------------------------
        # Power
        # ---------------------------------------------------------------------

        if [[ "$line" =~ ^power[0-9]+:[[:space:]]*([0-9.]+)[[:space:]]*mW[[:space:]]*\(avg[[:space:]]*=[[:space:]]*([0-9.]+)[[:space:]]*mW ]]; then

            SENSORS_POWER="${BASH_REMATCH[1]}"
            SENSORS_POWER_AVG="${BASH_REMATCH[2]}"

            continue

        fi

        if [[ "$line" =~ ^power[0-9]+:[[:space:]]*.*\(crit[[:space:]]*=[[:space:]]*([0-9.]+)[[:space:]]*W ]]; then

            SENSORS_POWER_CRIT="${BASH_REMATCH[1]}"

            continue

        fi

        # ---------------------------------------------------------------------
        # AMD GPU
        # ---------------------------------------------------------------------

        if [[ "$line" =~ ^vddgfx:[[:space:]]*([0-9.]+)[[:space:]]*mV ]]; then

            SENSORS_GPU_VDDGFX="${BASH_REMATCH[1]}"

            continue

        fi

        if [[ "$line" =~ ^vddnb:[[:space:]]*([0-9.]+)[[:space:]]*V ]]; then

            SENSORS_GPU_VDDNB="${BASH_REMATCH[1]}"

            continue

        fi

        if [[ "$line" =~ ^sclk:[[:space:]]*([0-9]+)[[:space:]]*MHz ]]; then

            SENSORS_GPU_SCLK="${BASH_REMATCH[1]}"

            continue

        fi

        # ---------------------------------------------------------------------
        # PWM
        # ---------------------------------------------------------------------

        if [[ "$line" =~ ^(pwm[0-9]+):[[:space:]]*([0-9]+)% ]]; then

            SENSORS_PWMS+=(
                "${BASH_REMATCH[1]}|${BASH_REMATCH[2]}"
            )

            continue

        fi

    done <<< "$output"

}

sensors_analyze() {

    SENSORS_STATUS="${SW_STATUS_OK}"

    if [[ "$SENSORS_AVAILABLE" != true ]]; then

        SENSORS_STATUS="${SW_STATUS_UNKNOWN}"

        return

    fi

    # -------------------------------------------------------------------------
    # Power status
    #
    # The value reported by sensors is mW while the critical threshold is W.
    # -------------------------------------------------------------------------

    if [[ -n "$SENSORS_POWER" && -n "$SENSORS_POWER_CRIT" ]]; then

        local power_w

        power_w="$(awk \
            -v value="$SENSORS_POWER" \
            'BEGIN { printf "%.3f", value / 1000 }')"

        local warning_w

        warning_w="$(awk \
            -v crit="$SENSORS_POWER_CRIT" \
            -v percent="$SENSORS_WARNING" \
            'BEGIN { printf "%.3f", crit * percent / 100 }')"

        if awk \
            -v value="$power_w" \
            -v crit="$SENSORS_POWER_CRIT" \
            'BEGIN { exit !(value >= crit) }'
        then

            SENSORS_STATUS="${SW_STATUS_CRITICAL}"

        elif awk \
            -v value="$power_w" \
            -v warning="$warning_w" \
            'BEGIN { exit !(value >= warning) }'
        then

            SENSORS_STATUS="${SW_STATUS_WARNING}"

        fi

    fi

}

sensors_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "Sensors"
    sw_state_set "module.icon" "lucide/gauge"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Availability
    # -------------------------------------------------------------------------

    sw_state_set "available" "${SENSORS_AVAILABLE}"

    # -------------------------------------------------------------------------
    # Power
    # -------------------------------------------------------------------------

    if [[ -n "$SENSORS_POWER" ]]; then

        sw_state_set "power" "${SENSORS_POWER}"

        sw_state_set "power.label" "Power"
        sw_state_set "power.widget" "line"
        sw_state_set "power.unit" "mW"
        sw_state_set "power.order" "10"

        [[ -n "$SENSORS_POWER_CRIT" ]] &&
            sw_state_set "power.critical" "$(
                awk \
                    -v value="$SENSORS_POWER_CRIT" \
                    'BEGIN { printf "%.0f", value * 1000 }'
            )"

    fi

    if [[ -n "$SENSORS_POWER_AVG" ]]; then

        sw_state_set "power_avg" "${SENSORS_POWER_AVG}"

        sw_state_set "power_avg.label" "Power average"
        sw_state_set "power_avg.widget" "line"
        sw_state_set "power_avg.unit" "mW"
        sw_state_set "power_avg.order" "20"
        sw_state_set "power_avg.scale" "fixed"

    fi

    # -------------------------------------------------------------------------
    # GPU
    # -------------------------------------------------------------------------

    if [[ -n "$SENSORS_GPU_VDDGFX" ]]; then

        sw_state_set "gpu.vddgfx" "${SENSORS_GPU_VDDGFX}"
        sw_state_set "gpu.vddgfx.label" "GPU voltage"
        sw_state_set "gpu.vddgfx.widget" "value"
        sw_state_set "gpu.vddgfx.unit" "mV"
        sw_state_set "gpu.vddgfx.order" "30"

    fi

    if [[ -n "$SENSORS_GPU_VDDNB" ]]; then

        sw_state_set "gpu.vddnb" "${SENSORS_GPU_VDDNB}"
        sw_state_set "gpu.vddnb.label" "GPU NB voltage"
        sw_state_set "gpu.vddnb.widget" "value"
        sw_state_set "gpu.vddnb.unit" "V"
        sw_state_set "gpu.vddnb.order" "40"

    fi

    if [[ -n "$SENSORS_GPU_SCLK" ]]; then

        sw_state_set "gpu.sclk" "${SENSORS_GPU_SCLK}"
        sw_state_set "gpu.sclk.label" "GPU clock"
        sw_state_set "gpu.sclk.widget" "line"
        sw_state_set "gpu.sclk.unit" "MHz"
        sw_state_set "gpu.sclk.order" "50"

    fi

    # -------------------------------------------------------------------------
    # Fans
    # -------------------------------------------------------------------------

    local fan
    local fan_name
    local fan_value
    local fan_alarm

    for fan in "${SENSORS_FANS[@]}"; do

        IFS='|' read -r fan_name fan_value fan_alarm <<< "$fan"

        sw_state_set "fan.${fan_name}" "$fan_value"
        sw_state_set "fan.${fan_name}.label" "${fan_name}"
        sw_state_set "fan.${fan_name}.widget" "line"
        sw_state_set "fan.${fan_name}.unit" "RPM"

        [[ "$fan_alarm" == "ALARM" ]] &&
            sw_state_set "fan.${fan_name}.alarm" "true"

    done

    # -------------------------------------------------------------------------
    # PWM
    # -------------------------------------------------------------------------

    local pwm
    local pwm_name
    local pwm_value

    for pwm in "${SENSORS_PWMS[@]}"; do

        IFS='|' read -r pwm_name pwm_value <<< "$pwm"

        sw_state_set "pwm.${pwm_name}" "$pwm_value"
        sw_state_set "pwm.${pwm_name}.label" "${pwm_name}"
        sw_state_set "pwm.${pwm_name}.widget" "line"
        sw_state_set "pwm.${pwm_name}.unit" "%"

    done

}

sensors_report() {

    if [[ "$SENSORS_AVAILABLE" != true ]]; then

        sw_log_info \
            "${MODULE_NAME}" \
            "sensors command unavailable"

        return

    fi

    local message="Hardware sensors"

    [[ -n "$SENSORS_POWER" ]] &&
        message+=" | Power: ${SENSORS_POWER} mW"

    [[ -n "$SENSORS_POWER_AVG" ]] &&
        message+=" | Avg: ${SENSORS_POWER_AVG} mW"

    sw_log_info \
        "${MODULE_NAME}" \
        "${message} (${SENSORS_STATUS})"

}

sw_module_run() {

    sw_state_use "sensors"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    sensors_collect

    sensors_analyze

    sw_status_update "${SENSORS_STATUS}" || return 1

    sensors_update_state

    sw_state_save

    sensors_report

local power_csv

power_csv="$(awk \
    -v value="$SENSORS_POWER" \
    'BEGIN { printf "%.0f", value }')"

sw_csv_append \
    "sensors" \
    "power" \
    "$power_csv"

    local power_avg_csv

power_avg_csv="$(awk \
    -v value="$SENSORS_POWER_AVG" \
    'BEGIN { printf "%.0f", value }')"

sw_csv_append \
    "sensors" \
    "power_avg" \
    "$power_avg_csv"
    

sw_csv_append \
    "sensors" \
    "gpu_sclk" \
    "${SENSORS_GPU_SCLK}"

sw_csv_append \
    "sensors" \
    "fan1" \
    "${SENSORS_FAN1}"

    # Optional CSV history.
    #
    # sw_csv_append \
    #     "sensors" \
    #     "power" \
    #     "${SENSORS_POWER}"

}