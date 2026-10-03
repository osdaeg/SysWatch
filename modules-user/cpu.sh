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

readonly MODULE_NAME="CPU"
readonly MODULE_DESCRIPTION="CPU usage monitoring"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-30}
MODULE_ORDER=${MODULE_ORDER:-10}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly CPU_WARNING="${CPU_WARNING:-80}"
readonly CPU_CRITICAL="${CPU_CRITICAL:-95}"
readonly CPU_SAMPLE_TIME="${CPU_SAMPLE_TIME:-1}"

# Number of prior readings (in addition to the current one) that must also
# breach the threshold before the status actually flips. This is what
# keeps a single spike from generating an event/notification.
readonly CPU_SUSTAINED_SAMPLES="${CPU_SUSTAINED_SAMPLES:-3}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

CPU_USAGE=0
CPU_STATUS="${SW_STATUS_UNKNOWN}"
CPU_PROCESS=()

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

cpu_top() {
    while read -r name cpu; do
        if [ "$name" != "ps" ]; then
            CPU_PROCESS+=("$name" "$cpu")
        fi
    done < <(ps -eo comm:25,%cpu --sort=-%cpu | head -n 10 | tail -n 9)
}

print_cpu_top() {
    local order=50

    for ((i = 0; i < ${#CPU_PROCESS[@]}; i += 2)); do
        #echo -e "${CPU_PROCESS[i]}\t\t${CPU_PROCESS[i+1]}%"
        sw_state_set "${CPU_PROCESS[i]}" "${CPU_PROCESS[i + 1]}"
        sw_state_set "${CPU_PROCESS[i]}.label" "${CPU_PROCESS[i]}"
        sw_state_set "${CPU_PROCESS[i]}.order" "$order"
        sw_state_set "${CPU_PROCESS[i]}.unit" "%"
        ((order += 10))
    done
}

cpu_collect() {

    local user1 nice1 system1 idle1 iowait1 irq1 softirq1 steal1
    local user2 nice2 system2 idle2 iowait2 irq2 softirq2 steal2

    local idle_delta
    local total_delta

    read -r _ \
        user1 nice1 system1 idle1 iowait1 irq1 softirq1 steal1 _ \
        </proc/stat

    sleep "${CPU_SAMPLE_TIME}"

    read -r _ \
        user2 nice2 system2 idle2 iowait2 irq2 softirq2 steal2 _ \
        </proc/stat

    idle_delta=$(((idle2 + iowait2) - (idle1 + iowait1)))

    total_delta=$(((\
        user2 + nice2 + system2 + idle2 + iowait2 + irq2 + softirq2 + steal2) - (\
        user1 + nice1 + system1 + idle1 + iowait1 + irq1 + softirq1 + steal1)))

    if ((total_delta == 0)); then

        CPU_USAGE=0
        return

    fi

    CPU_USAGE=$(((100 * (total_delta - idle_delta)) / total_delta))

}

cpu_analyze() {

    CPU_STATUS="${SW_STATUS_OK}"

    if ((CPU_USAGE >= CPU_CRITICAL)) &&
        sw_csv_all_above cpu usage "${CPU_CRITICAL}" "${CPU_SUSTAINED_SAMPLES}"; then

        CPU_STATUS="${SW_STATUS_CRITICAL}"

    elif ((CPU_USAGE >= CPU_WARNING)) &&
        sw_csv_all_above cpu usage "${CPU_WARNING}" "${CPU_SUSTAINED_SAMPLES}"; then

        CPU_STATUS="${SW_STATUS_WARNING}"

    fi

}

cpu_update_state() {

    sw_state_set module_version "${MODULE_VERSION}"

    sw_state_set cores "$(nproc)"

    sw_state_set load1 "$(cut -d' ' -f1 /proc/loadavg)"
    sw_state_set load5 "$(cut -d' ' -f2 /proc/loadavg)"
    sw_state_set load15 "$(cut -d' ' -f3 /proc/loadavg)"

    # -------------------------------------------------------------------------
    # Module metadata
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "$(sw_translate "CPU")"
    sw_state_set "module.icon" "lucide/cpu"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Data
    # -------------------------------------------------------------------------

    sw_state_set "usage" "${CPU_USAGE}"

    sw_state_set "usage.label" "$(sw_translate "Usage")"
    sw_state_set "usage.widget" "line"
    sw_state_set "usage.unit" "%"
    sw_state_set "usage.order" "10"
    sw_state_set "usage.warning" "${CPU_WARNING}"
    sw_state_set "usage.critical" "${CPU_CRITICAL}"
    sw_state_set "usage.scale" "fixed"
    sw_state_set "usage.min" "0"
    sw_state_set "usage.max" "100"

    sw_state_set "cores.label" "$(sw_translate "Cores")"
    sw_state_set "cores.order" "15"

    sw_state_set "load1.label" "$(sw_translate "Load: 1 minute")"
    sw_state_set "load1.order" "20"
    sw_state_set "load5.label" "$(sw_translate "Load: 5 minutes")"
    sw_state_set "load5.order" "30"
    sw_state_set "load15.label" "$(sw_translate "Load: 15 minutes")"
    sw_state_set "load15.order" "40"
}

cpu_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "CPU usage: ${CPU_USAGE}% (${CPU_STATUS})"

}

sw_module_run() {

    sw_state_use "cpu"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    #sw_state_remote "$MODULE_REMOTE"

    sw_state_load

    cpu_collect

    cpu_analyze

    sw_status_update "${CPU_STATUS}" || return 1

    cpu_update_state

    sw_csv_append \
        "cpu" \
        "usage" \
        "${CPU_USAGE}"

    sw_state_save

    sw_state_clear

    (
        sw_state_use "top"

        #sw_state_remote "$MODULE_REMOTE"

        if [ "$CPU_USAGE" -gt 80 ]; then

            #sw_state_delete

            sw_state_reset

            sw_state_set module_version "${MODULE_VERSION}"
            sw_state_set "module.label" "$(sw_translate "Processes")"
            sw_state_set "module.icon" "lucide/rows-4"
            sw_state_set "module.order" "900"

            cpu_top

            print_cpu_top

            sw_state_set "status" "WARNING"

            if [ "$CPU_USAGE" -gt 95 ]; then
                sw_state_set "status" "CRITICAL"
            fi

            sw_state_save

        else

            sw_state_delete
            #sw_state_set "Estado"  " No hay aplicaciones con uso elevado de CPU: ${CPU_USAGE}%"
            #sw_state_set "Estado.label" "$(sw_translate "Estado:"
            #sw_state_set "Estado.order" "20"
        fi

        #sw_state_save
    )

    cpu_report

}
