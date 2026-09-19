#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Memory monitoring module
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Memory"
readonly MODULE_DESCRIPTION="Memory usage monitoring"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-240}
MODULE_ORDER=${MODULE_ORDER:-20}
MODULE_REMOTE=${MODULE_REMOTE:-""}


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly MEMORY_WARNING="${MEMORY_WARNING:-80}"
readonly MEMORY_CRITICAL="${MEMORY_CRITICAL:-95}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

MEMORY_TOTAL_MB=0
MEMORY_USED_MB=0
MEMORY_AVAILABLE_MB=0
MEMORY_USAGE=0

MEMORY_STATUS="${SW_STATUS_UNKNOWN}"
MEMORY_PROCESS=()

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

memory_top() {
    while read -r pid name mem; do
        MEMORY_PROCESS+=("$pid" "$name" "$mem")
    done < <(ps -eo pid,comm:25,%mem --sort=-%mem | sed -n '2,9p')
}

print_memory_top() {
    local order=50
    
    for ((i=0; i<${#MEMORY_PROCESS[@]}; i+=3)); do
        #echo -e "${MEMORY_PROCESS[i]}\t\t${MEMORY_PROCESS[i+2]}%"
        sw_state_set "${MEMORY_PROCESS[i+1]}"  "${MEMORY_PROCESS[i+2]}"
        sw_state_set "${MEMORY_PROCESS[i+1]}.label"  "${MEMORY_PROCESS[i+1]} (${MEMORY_PROCESS[i]})"
        sw_state_set "${MEMORY_PROCESS[i+1]}.order" "$order"
        sw_state_set "${MEMORY_PROCESS[i+1]}.unit" "%"
        ((order += 10))
    done
}

memory_collect() {

    local total_kb
    local available_kb

    total_kb=$(
        awk '/^MemTotal:/ {print $2}' /proc/meminfo
    )

    available_kb=$(
        awk '/^MemAvailable:/ {print $2}' /proc/meminfo
    )

    MEMORY_TOTAL_MB=$(( total_kb / 1024 ))
    MEMORY_AVAILABLE_MB=$(( available_kb / 1024 ))
    MEMORY_USED_MB=$(( MEMORY_TOTAL_MB - MEMORY_AVAILABLE_MB ))

    MEMORY_USAGE=$(( MEMORY_USED_MB * 100 / MEMORY_TOTAL_MB ))

}

memory_analyze() {

    MEMORY_STATUS="${SW_STATUS_OK}"

    if (( MEMORY_USAGE >= MEMORY_CRITICAL )); then

        MEMORY_STATUS="${SW_STATUS_CRITICAL}"

    elif (( MEMORY_USAGE >= MEMORY_WARNING )); then

        MEMORY_STATUS="${SW_STATUS_WARNING}"

    fi

}

memory_update_state() {

    sw_state_set module_version "${MODULE_VERSION}"

    sw_state_set total_mb "${MEMORY_TOTAL_MB}"
    sw_state_set used_mb "${MEMORY_USED_MB}"
    sw_state_set available_mb "${MEMORY_AVAILABLE_MB}"

    sw_state_set usage "${MEMORY_USAGE}"
    
    # -------------------------------------------------------------------------
    # Module metadata
    # -------------------------------------------------------------------------
    
    sw_state_set "module.label" "Memoria"
    sw_state_set "module.icon" "lucide/memory"
    sw_state_set "module.order" "$MODULE_ORDER"
    
    sw_state_set "usage.widget" "gauge"
    sw_state_set "usage.unit" "%"
    sw_state_set "usage.order" "10"
    sw_state_set "usage.label" "Uso"
    
    sw_state_set "total_mb.label" "Total"
    sw_state_set "total_mb.order" "20"
    sw_state_set "used_mb.label" "Usada"
    sw_state_set "used_mb.order" "30"
    sw_state_set "available_mb.label" "Disponible"
    sw_state_set "available_mb.order" "40"

}

memory_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Memory usage: ${MEMORY_USAGE}% (${MEMORY_STATUS})"

}

sw_module_run() {

    sw_state_use "memory"

    sw_state_load

    memory_collect

    memory_analyze

    sw_status_update "${MEMORY_STATUS}" || return 1

    memory_update_state

    sw_state_save

    sw_state_clear
    
    (
    sw_state_use "top_memory"
    
    
    if [ "$MEMORY_USAGE" -gt 79 ]; then
    
        sw_state_reset
    
        sw_state_set module_version "${MODULE_VERSION}"
        sw_state_set "module.label" "Procesos en memoria"
        sw_state_set "module.icon" "lucide/rows-4"
        sw_state_set "module.order" "900"
        
        memory_top
      
        print_memory_top
        
        sw_state_set "status" "WARNING"
        
        if [ "$MEMORY_USAGE" -gt 94 ]; then
            sw_state_set "status" "CRITICAL"
        fi
        
        sw_state_save
        
    else

        #sw_state_set "Estado"  " No hay aplicaciones con uso elevado de memoria: ${MEMORY_USAGE}%"
        #sw_state_set "Estado.label"  "Estado:"
        #sw_state_set "Estado.order" "20"
        sw_state_delete
    fi
    
    #sw_state_save
    )


    memory_report
    
    sw_csv_append \
        "memory" \
        "used" \
        "${MEMORY_USED_MB}"

}
