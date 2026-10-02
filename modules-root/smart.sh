#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# CPU monitoring module
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="SMART"
readonly MODULE_DESCRIPTION="SMART disk health monitoring"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-86400}
MODULE_ORDER=${MODULE_ORDER:-41}
MODULE_REMOTE=${MODULE_REMOTE:-""}


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly SMART_WARNING="${SMART_WARNING:-80}"
readonly SMART_CRITICAL="${SMART_CRITICAL:-95}"
readonly SMART_SAMPLE_TIME="${SMART_SAMPLE_TIME:-0.2}"

readonly SMART_WARNING_TEMPERATURE="${SMART_WARNING_TEMPERATURE:-50}"
readonly SMART_CRITICAL_TEMPERATURE="${SMART_CRITICAL_TEMPERATURE:-60}"

readonly SMART_WARNING_LIFE_LEFT="${SMART_WARNING_LIFE_LEFT:-20}"
readonly SMART_CRITICAL_LIFE_LEFT="${SMART_CRITICAL_LIFE_LEFT:-10}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

SMART_DEVICES=()

# Identification
SMART_MODEL=()
SMART_SERIAL=()
SMART_CAPACITY=()

# Overall health
SMART_HEALTH=()

# Telemetry
SMART_TEMPERATURE=()
SMART_POWER_ON_HOURS=()
SMART_POWER_CYCLE_COUNT=()
SMART_PERCENT_USED=()
SMART_LIFE_LEFT=()

# Degradation indicators
SMART_REALLOCATED=()
SMART_PENDING=()
SMART_UNCORRECTABLE=()
SMART_MEDIA_ERRORS=()
SMART_CRITICAL_WARNING=()

SMART_DEVICE_COUNT=0

SMART_STATUS="UNKNOWN"

SMART_STATUS=()
SMART_GLOBAL_STATUS="${SW_STATUS_OK}"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

smart_collect() {
    
    sw_require_command smartctl || return 127

    mapfile -t SMART_DEVICES < <(

        smartctl --scan \
            | awk '{print $1}'

    )

    SMART_DEVICE_COUNT="${#SMART_DEVICES[@]}"

    SMART_HEALTH=()

    SMART_MODEL=()
    SMART_SERIAL=()
    SMART_CAPACITY=()

    SMART_TEMPERATURE=()

    SMART_POWER_ON_HOURS=()
    SMART_POWER_CYCLE_COUNT=()
    SMART_PERCENT_USED=()
    SMART_LIFE_LEFT=()

    SMART_REALLOCATED=()
    SMART_PENDING=()
    SMART_UNCORRECTABLE=()

    SMART_MEDIA_ERRORS=()
    SMART_CRITICAL_WARNING=()

    local device
    local info
    local attributes
    local value

    for device in "${SMART_DEVICES[@]}"; do

        info="$(
            smartctl -Hi "${device}" 2>/dev/null
        )"

        attributes="$(
            smartctl -A "${device}" 2>/dev/null
        )"

        # ---------------------------------------------------------------------
        # Overall health
        # ---------------------------------------------------------------------

        value="$(
            awk '
                /SMART overall-health self-assessment test result:/ {print $NF}
                /SMART Health Status:/ {print $NF}
            ' <<< "${info}"
        )"

        [[ -n "${value}" ]] || value="UNKNOWN"

        SMART_HEALTH+=("${value}")

        # ---------------------------------------------------------------------
        # Identification
        # ---------------------------------------------------------------------

        SMART_MODEL+=("$(
            awk -F: '
                /^Device Model:/ {
                    gsub(/^[ \t]+/, "", $2)
                    print $2
                }

                /^Model Number:/ {
                    gsub(/^[ \t]+/, "", $2)
                    print $2
                }
            ' <<< "${info}"
        )")

        SMART_SERIAL+=("$(
            awk -F: '
                /^Serial Number:/ {
                    gsub(/^[ \t]+/, "", $2)
                    print $2
                }
            ' <<< "${info}"
        )")

        SMART_CAPACITY+=("$(
            awk -F: '
                /^User Capacity:/ {
                    gsub(/^[ \t]+/, "", $2)
                    sub(/ \[.*/, "", $2)
                    gsub(/,/, "", $2)
                    sub(/ bytes/, "", $2)
                    print $2
                }
            ' <<< "${info}"
        )")

        # ---------------------------------------------------------------------
        # Telemetry
        # ---------------------------------------------------------------------

        SMART_TEMPERATURE+=("$(
            awk '

                /^194 Temperature_Celsius/ {
                    print $10
                    exit
                }

                /^190 Airflow_Temperature_Cel/ {
                    print $10
                    exit
                }

                /^Temperature:/ {
                    print $2
                    exit
                }

            ' <<< "${attributes}"
        )")

        SMART_POWER_ON_HOURS+=("$(
            awk '
                /^ *9 Power_On_Hours/ {
                    print $10
                    exit
                }
            ' <<< "${attributes}"
        )")

        SMART_POWER_CYCLE_COUNT+=("$(
            awk '
                /^ *12 Power_Cycle_Count/ {
                    print $10
                    exit
                }
            ' <<< "${attributes}"
        )")

        SMART_PERCENT_USED+=("$(
            awk '
                /^Percentage Used:/ {
                    print $3
                    exit
                }
            ' <<< "${attributes}"
        )")
        
        SMART_LIFE_LEFT+=("$(
            awk '
                /^231 SSD_Life_Left/ {
                     print $10
                     exit
                }
            ' <<< "${attributes}"
        )")
        
        # ---------------------------------------------------------------------
        # Degradation indicators
        # ---------------------------------------------------------------------

        SMART_REALLOCATED+=("$(
            awk '
                /^ *5 Reallocated_Sector_Ct/ {
                    print $10
                    exit
                }
            ' <<< "${attributes}"
        )")

        SMART_PENDING+=("$(
            awk '
                /^197 Current_Pending_Sector/ {
                    print $10
                    exit
                }
            ' <<< "${attributes}"
        )")

        SMART_UNCORRECTABLE+=("$(
            awk '
                /^198 Offline_Uncorrectable/ {
                    print $10
                    exit
                }
            ' <<< "${attributes}"
        )")

        SMART_MEDIA_ERRORS+=("$(
            awk '
                /^Media and Data Integrity Errors:/ {
                    print $NF
                    exit
                }
            ' <<< "${attributes}"
        )")

        SMART_CRITICAL_WARNING+=("$(
            awk '
                /^Critical Warning:/ {
                    print $3
                    exit
                }
            ' <<< "${attributes}"
        )")

    done

}

smart_analyze() {

    SMART_GLOBAL_STATUS="${SW_STATUS_OK}"

    local i

    for (( i=0; i<SMART_DEVICE_COUNT; i++ )); do

        SMART_STATUS[$i]="${SW_STATUS_OK}"

        #
        # SMART self-assessment
        #

        if [[ "${SMART_HEALTH[$i]}" != "PASSED" ]]; then

            SMART_STATUS[$i]="${SW_STATUS_CRITICAL}"

        fi

        #
        # Temperature
        #

        if [[ -n "${SMART_TEMPERATURE[$i]}" ]]; then

            if (( SMART_TEMPERATURE[$i] >= SMART_CRITICAL_TEMPERATURE )); then

                SMART_STATUS[$i]="${SW_STATUS_CRITICAL}"

            elif (( SMART_TEMPERATURE[$i] >= SMART_WARNING_TEMPERATURE )) &&
                 [[ "${SMART_STATUS[$i]}" == "${SW_STATUS_OK}" ]]; then

                SMART_STATUS[$i]="${SW_STATUS_WARNING}"

            fi

        fi

        #
        # Pending sectors
        #

        if [[ -n "${SMART_PENDING[$i]}" ]] &&
           (( SMART_PENDING[$i] > 0 )) &&
           [[ "${SMART_STATUS[$i]}" == "${SW_STATUS_OK}" ]]; then

            SMART_STATUS[$i]="${SW_STATUS_WARNING}"

        fi

        #
        # Offline uncorrectable
        #

        if [[ -n "${SMART_UNCORRECTABLE[$i]}" ]] &&
           (( SMART_UNCORRECTABLE[$i] > 0 )); then

            SMART_STATUS[$i]="${SW_STATUS_CRITICAL}"

        fi

        #
        # Media errors
        #

        if [[ -n "${SMART_MEDIA_ERRORS[$i]}" ]] &&
           (( SMART_MEDIA_ERRORS[$i] > 0 )); then

            SMART_STATUS[$i]="${SW_STATUS_CRITICAL}"

        fi

        #
        # SSD life left
        #

        if [[ -n "${SMART_LIFE_LEFT[$i]}" ]]; then

            if (( SMART_LIFE_LEFT[$i] <= SMART_CRITICAL_LIFE_LEFT )); then

                SMART_STATUS[$i]="${SW_STATUS_CRITICAL}"

            elif (( SMART_LIFE_LEFT[$i] <= SMART_WARNING_LIFE_LEFT )) &&
                 [[ "${SMART_STATUS[$i]}" == "${SW_STATUS_OK}" ]]; then

                SMART_STATUS[$i]="${SW_STATUS_WARNING}"

            fi

        fi

        #
        # Update global status
        #

        case "${SMART_STATUS[$i]}" in

            "${SW_STATUS_CRITICAL}")

                SMART_GLOBAL_STATUS="${SW_STATUS_CRITICAL}"
                ;;

            "${SW_STATUS_WARNING}")

                [[ "${SMART_GLOBAL_STATUS}" == "${SW_STATUS_OK}" ]] &&
                    SMART_GLOBAL_STATUS="${SW_STATUS_WARNING}"
                ;;

        esac

    done

}

smart_update_state() {

    #sw_state_set "module_version" "${MODULE_VERSION}"

    #sw_state_set "device_count" "${SMART_DEVICE_COUNT}"

    local i
    local orden

    for (( i=0; i<SMART_DEVICE_COUNT; i++ )); do
    
        sw_state_use "${SMART_SERIAL[$i]}"

        if [[ -n "$MODULE_REMOTE" ]]; then
                sw_state_remote "$MODULE_REMOTE"
        fi
        
        sw_state_load
        
        sw_state_set "module_version" "${MODULE_VERSION}"
        
        sw_state_set "module.label" "${SMART_MODEL[$i]}"
        sw_state_set "module.icon" "lucide/hard-drive"
        
        #orden = $((i + 40))
        sw_state_set "module.order" "$MODULE_ORDER"

        #sw_state_set "device_count" "${SMART_DEVICE_COUNT}"

        # ---------------------------------------------------------------------
        # Identification
        # ---------------------------------------------------------------------

        sw_state_set \
            "device" \
            "${SMART_DEVICES[$i]}"
        sw_state_set "device.label" "$(sw_translate "Device")"

        #sw_state_set \
        #    "model" \
        #    "${SMART_MODEL[$i]}"

        sw_state_set \
            "serial" \
            "${SMART_SERIAL[$i]}"
        sw_state_set "serial.label" "# Serie"    
        
        GB=$(bc <<< "scale=2; "${SMART_CAPACITY[$i]}" / 1000000000")
        GIB=$(bc <<< "scale=2; "${SMART_CAPACITY[$i]}" / 1073741824")

        sw_state_set \
            "capacity" \
            "${GIB}"
        sw_state_set "capacity.label" "$(sw_translate "Capacity")"
        sw_state_set "capacity.unit" "Gb"

        # ---------------------------------------------------------------------
        # Overall health
        # ---------------------------------------------------------------------

        sw_state_set \
            "health" \
            "${SMART_HEALTH[$i]}"
        #sw_state_set "health.icon" "lucide/hearth"
        sw_state_set "health.label" "$(sw_translate "Health")"
        
        sw_state_set "status" "${SMART_STATUS[$i]}"

        # ---------------------------------------------------------------------
        # Telemetry
        # ---------------------------------------------------------------------

        sw_state_set \
            "temperature" \
            "${SMART_TEMPERATURE[$i]}"
        #sw_state_set "temperature.icon" "lucide/thermometer"  
        sw_state_set "temperature.label" "$(sw_translate "Temperature")"
        sw_state_set "temperature.unit" "ºC"  

        sw_state_set \
            "power_on_hours" \
            "${SMART_POWER_ON_HOURS[$i]}"
        #sw_state_set "power_on_hours.icon" "lucide/clock" 
        sw_state_set "power_on_hours.label" "$(sw_translate "Operating time")"
        sw_state_set "power_on_hours.unit" "hs"  

        sw_state_set \
            "power_cycle_count" \
            "${SMART_POWER_CYCLE_COUNT[$i]}"
        sw_state_set "power_cycle_count.label" "$(sw_translate "Counter")"

        sw_state_set \
            "percent_used" \
            "${SMART_PERCENT_USED[$i]}"
        sw_state_set "percent_used.label" "$(sw_translate "% Used")"
        sw_state_set "percent_used.unit" "%"
            
        sw_state_set \
            "life_left" \
            "${SMART_LIFE_LEFT[$i]}" 
        sw_state_set "life_left.label" "$(sw_translate "Lifetime")"
        sw_state_set "life_left.unit" "%" 

        # ---------------------------------------------------------------------
        # Degradation indicators
        # ---------------------------------------------------------------------

        sw_state_set \
            "reallocated" \
            "${SMART_REALLOCATED[$i]}"
        sw_state_set "reallocated.label" "$(sw_translate "Reallocated")"

        sw_state_set \
            "pending" \
            "${SMART_PENDING[$i]}"
        sw_state_set "pending.label" "$(sw_translate "Pending")"

        sw_state_set \
            "uncorrectable" \
            "${SMART_UNCORRECTABLE[$i]}"
        sw_state_set "uncorrectable.label" "$(sw_translate "Uncorrectable")"         

        sw_state_set \
            "media_errors" \
            "${SMART_MEDIA_ERRORS[$i]}"
        sw_state_set "media_errors.label" "$(sw_translate "Average number of errors")"    

        sw_state_set \
            "critical_warning" \
            "${SMART_CRITICAL_WARNING[$i]}"
        sw_state_set "critical_warning.label" "$(sw_translate "Critical alerts")"       
            
        sw_state_save    
        
        sw_csv_append \
            "${SMART_SERIAL[$i]}" \
            "temperature" \
            "${SMART_TEMPERATURE[$i]}"

    done

}
smart_report() {

    local summary=""
    local i

    for (( i=0; i<SMART_DEVICE_COUNT; i++ )); do

        [[ -n "${summary}" ]] && summary+=", "

        summary+="${SMART_DEVICES[$i]}=${SMART_HEALTH[$i]}"

    done

    sw_log_info \
        "${MODULE_NAME}" \
        "SMART: ${SMART_DEVICE_COUNT} device(s): ${summary}"

}

sw_module_run() {

    #sw_state_use "smart"
    #sw_state_load

    smart_collect || return 1

    smart_analyze

    sw_status_update "${SMART_GLOBAL_STATUS}" || return 1

    smart_update_state

    #sw_state_save

    smart_report

}
