#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch - Disk I/O
#
# Shows physical disk pressure and top processes writing to disk.
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Disk IO"
readonly MODULE_DESCRIPTION="Disk I/O and top writers"
readonly MODULE_VERSION="0.2.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-1000}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Thresholds
# -----------------------------------------------------------------------------

readonly DISK_UTIL_WARNING=70
readonly DISK_UTIL_CRITICAL=90

readonly DISK_AWAIT_WARNING=20
readonly DISK_AWAIT_CRITICAL=50

# Await only affects status when there is meaningful I/O activity.
readonly DISK_AWAIT_MIN_IOPS=10

# -----------------------------------------------------------------------------
# Runtime data
# -----------------------------------------------------------------------------

DISK_PROCESS=()
DISK_STATS=()
DISK_STATUS="OK"

# -----------------------------------------------------------------------------
# Trim command
# -----------------------------------------------------------------------------

disk_trim_command() {

    local cmd="$1"

    if ((${#cmd} > 70)); then
        printf "%.67s..." "$cmd"
    else
        printf "%s" "$cmd"
    fi

}

# -----------------------------------------------------------------------------
# Collect top writing processes
# -----------------------------------------------------------------------------

disk_collect_processes() {

    DISK_PROCESS=()

    while read -r write_kib pid; do

        local cmd

        cmd="$(ps -p "$pid" -o comm=)"

        [[ -n "$cmd" ]] || continue

        DISK_PROCESS+=("$cmd" "$write_kib")

    done < <(

        LC_ALL=C pidstat -d 1 5 |
            awk '
        $1=="Average:" &&
        $2+0==$2 &&
        $5>0 {
            print $5, $3
        }' |
            sort -nr |
            head -8

    )

}

# -----------------------------------------------------------------------------
# Collect physical disk statistics
#
# Output per device:
#
#   device util await aqu-sz iops
#
# await is weighted between read and write latency.
# -----------------------------------------------------------------------------

disk_collect_stats() {

    DISK_STATS=()

    local stats

    stats="$(
        LC_ALL=C iostat -dx 1 2 2>/dev/null |
            awk '
        $1=="Device" {

            sample++

            for (i=1; i<=NF; i++) {

                if ($i=="r/s")       r=i
                else if ($i=="w/s") w=i
                else if ($i=="r_await") r_await=i
                else if ($i=="w_await") w_await=i
                else if ($i=="aqu-sz") aqu_sz=i
                else if ($i=="%util") util=i

            }

            next
        }

        
        sample==2 &&
            r && w && r_await && w_await && aqu_sz && util &&
            $1 ~ /^[[:alpha:]]/ &&
            $1 !~ /^(loop|zram|ram|sr|dm-)/ {

            iops=$(r)+$(w)

            if (iops > 0) {
                await=(($(r)*$(r_await))+($(w)*$(w_await)))/iops
            } else {
                await=0
            }

            printf "%s %.2f %.2f %.2f %.2f\n",
                   $1,
                   $(util),
                   await,
                   $(aqu_sz),
                   iops
        }
        '
    )"

    while read -r device util await aqusz iops; do

        [[ -n "$device" ]] || continue

        DISK_STATS+=(
            "$device"
            "$util"
            "$await"
            "$aqusz"
            "$iops"
        )

    done <<<"$stats"

}

# -----------------------------------------------------------------------------
# Evaluate disk status
# -----------------------------------------------------------------------------

disk_evaluate_status() {

    DISK_STATUS="OK"

    if ((${#DISK_STATS[@]} == 0)); then

        DISK_STATUS="WARNING"

        sw_log_info \
            "${MODULE_NAME}" \
            "No physical disk statistics available"

        return

    fi

    for ((i = 0; i < ${#DISK_STATS[@]}; i += 5)); do

        local device="${DISK_STATS[i]}"
        local util="${DISK_STATS[i + 1]}"
        local await="${DISK_STATS[i + 2]}"
        local iops="${DISK_STATS[i + 4]}"

        # CRITICAL ------------------------------------------------------------

        if awk \
            -v util="$util" \
            -v await="$await" \
            -v iops="$iops" \
            -v util_limit="$DISK_UTIL_CRITICAL" \
            -v await_limit="$DISK_AWAIT_CRITICAL" \
            -v min_iops="$DISK_AWAIT_MIN_IOPS" \
            'BEGIN {
        exit !(util >= util_limit || (await >= await_limit && iops >= min_iops))
    }'; then
            DISK_STATUS="CRITICAL"
            continue
        fi

        # WARNING -------------------------------------------------------------

        if [[ "$DISK_STATUS" != "CRITICAL" ]] &&
            awk \
                -v util="$util" \
                -v await="$await" \
                -v iops="$iops" \
                -v util_limit="$DISK_UTIL_WARNING" \
                -v await_limit="$DISK_AWAIT_WARNING" \
                -v min_iops="$DISK_AWAIT_MIN_IOPS" \
                'BEGIN {
        exit !(util >= util_limit || (await >= await_limit && iops >= min_iops))
    }'; then
            DISK_STATUS="WARNING"
        fi
    done

}

# -----------------------------------------------------------------------------
# Update SysWatch state
# -----------------------------------------------------------------------------

disk_update_state() {

    local order=20
    local index=1
    local process_order=1000

    sw_state_set module_version "${MODULE_VERSION}"

    sw_state_set "module.label" "$(sw_translate "Disk I/O")"
    sw_state_set "module.icon" "lucide/hard-drive"
    sw_state_set "module.order" "$MODULE_ORDER"

    sw_state_set "status.label" "$(sw_translate "Status")"
    sw_state_set "status.order" "10"

    sw_status_update "$DISK_STATUS" || return 1

    # -------------------------------------------------------------------------
    # Physical disks
    # -------------------------------------------------------------------------

    for ((i = 0; i < ${#DISK_STATS[@]}; i += 5)); do

        local device="${DISK_STATS[i]}"
        local util="${DISK_STATS[i + 1]}"
        local await="${DISK_STATS[i + 2]}"
        local aqusz="${DISK_STATS[i + 3]}"

        sw_state_set \
            "disk_${index}" \
            "$util"

        sw_state_set \
            "disk_${index}.label" \
            "${device} · $(sw_translate "Utilization")"

        sw_state_set \
            "disk_${index}.unit" \
            "%"

        sw_state_set \
            "disk_${index}.order" \
            "$order"

        ((order += 10))

        sw_state_set \
            "disk_${index}_await" \
            "$await"

        sw_state_set \
            "disk_${index}_await.label" \
            "${device} · $(sw_translate "Await")"

        sw_state_set \
            "disk_${index}_await.unit" \
            "ms"

        sw_state_set \
            "disk_${index}_await.order" \
            "$order"

        ((order += 10))

        sw_state_set \
            "disk_${index}_queue" \
            "$aqusz"

        sw_state_set \
            "disk_${index}_queue.label" \
            "${device} · $(sw_translate "Queue")"

        sw_state_set \
            "disk_${index}_queue.unit" \
            ""

        sw_state_set \
            "disk_${index}_queue.order" \
            "$order"

        ((order += 10))
        ((index++))

    done

    # -------------------------------------------------------------------------
    # Top writing processes
    # -------------------------------------------------------------------------

    ((order += 10))

    sw_state_set "process_header" "-------------------------"
    sw_state_set "process_header.label" "$(sw_translate "Processes")"
    sw_state_set "process_header.order" "${order}"
    sw_state_set "process_header.color" "blue"

    index=1

    for ((i = 0; i < ${#DISK_PROCESS[@]}; i += 2)); do

        local command="${DISK_PROCESS[i]}"
        local write="${DISK_PROCESS[i + 1]}"

        sw_state_set \
            "process_${index}" \
            "$write"

        sw_state_set \
            "process_${index}.label" \
            "$command"

        sw_state_set \
            "process_${index}.unit" \
            "KiB/s"

        sw_state_set \
            "process_${index}.order" \
            "$process_order"

        ((index++))
        ((process_order += 10))

    done

}

# -----------------------------------------------------------------------------
# Report
# -----------------------------------------------------------------------------

disk_report() {

    local process_count=$((${#DISK_PROCESS[@]} / 2))
    local device_count=$((${#DISK_STATS[@]} / 5))

    sw_log_info \
        "${MODULE_NAME}" \
        "Status=${DISK_STATUS}, devices=${device_count}, top_writers=${process_count}"

}

# -----------------------------------------------------------------------------
# Module entry point
# -----------------------------------------------------------------------------

sw_module_run() {

    (

        sw_state_use "diskio_top"

        # SW_STATE is a single global array shared by every module in this
        # run. sw_state_reset only truncates the FILE; it doesn't clear the
        # in-memory array. Without sw_state_clear, fields from the previous
        # module could leak into diskio_top.state.

        sw_state_clear
        sw_state_reset

        disk_collect_processes

        disk_collect_stats

        disk_evaluate_status

        disk_update_state

        sw_state_save

        disk_report

    )

}
