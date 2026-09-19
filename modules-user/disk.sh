#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Disk usage monitoring module
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Disk"
readonly MODULE_DESCRIPTION="Disk usage monitoring"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-40}
MODULE_REMOTE=${MODULE_REMOTE:-""}


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly DISK_WARNING="${DISK_WARNING:-85}"
readonly DISK_CRITICAL="${DISK_CRITICAL:-95}"

# Prior readings (besides the current one) that must also breach the
# threshold before the status actually flips -- same debounce pattern as
# cpu.sh, using sw_csv_all_above().
readonly DISK_SUSTAINED_SAMPLES="${DISK_SUSTAINED_SAMPLES:-3}"

# Skip FUSE-backed mounts (fuse.rclone, fuse.sshfs, fuse.gvfsd-fuse...).
# These often report bogus sizes (a cloud remote "having" a petabyte free)
# and usually aren't what you want a disk-space alert for.
readonly DISK_EXCLUDE_FUSE="${DISK_EXCLUDE_FUSE:-true}"

# Comma-separated list of exact mountpoints to always skip,
# e.g. "/boot/efi,/mnt/iso".
readonly DISK_EXCLUDE_MOUNTS="${DISK_EXCLUDE_MOUNTS:-}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

DISK_KEYS=()
DISK_MOUNTPOINT=()
DISK_FSTYPE=()

DISK_TOTAL=()
DISK_USED=()
DISK_AVAIL=()
DISK_USE_PCT=()

DISK_STATUS=()

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

disk_sanitize_key() {

    local mountpoint="$1"

    if [[ "${mountpoint}" == "/" ]]; then

        printf 'root\n'
        return

    fi

    local key="${mountpoint#/}"
    key="${key//\//_}"

    printf '%s\n' "${key}"

}

disk_is_excluded_mount() {

    local mountpoint="$1"

    [[ -z "${DISK_EXCLUDE_MOUNTS}" ]] && return 1

    local IFS=','
    local excluded

    for excluded in ${DISK_EXCLUDE_MOUNTS}; do

        [[ "${mountpoint}" == "${excluded}" ]] && return 0

    done

    return 1

}

disk_discover() {

    local line
    local fs
    local fstype
    local blocks
    local used
    local avail
    local pct
    local mountpoint

    DISK_KEYS=()
    DISK_MOUNTPOINT=()
    DISK_FSTYPE=()
    DISK_TOTAL=()
    DISK_USED=()
    DISK_AVAIL=()
    DISK_USE_PCT=()

    while read -r fs fstype blocks used avail pct mountpoint
    do

        [[ "${fs}" == "Filesystem" ]] && continue

        # Skip pseudo/virtual filesystems by mountpoint prefix -- more
        # reliable across distros than trying to enumerate every fstype.
        case "${mountpoint}" in

            /proc*|/sys*|/dev*|/run*|/snap*)

                continue
                ;;

        esac

        [[ -z "${mountpoint}" ]] && continue

        if [[ "${DISK_EXCLUDE_FUSE}" == "true" && "${fstype}" == fuse.* ]]; then

            continue

        fi

        disk_is_excluded_mount "${mountpoint}" && continue

        DISK_KEYS+=("$(disk_sanitize_key "${mountpoint}")")
        DISK_MOUNTPOINT+=("${mountpoint}")
        DISK_FSTYPE+=("${fstype}")

        # 1024-blocks -> bytes
        DISK_TOTAL+=("$(( blocks * 1024 ))")
        DISK_USED+=("$(( used * 1024 ))")
        DISK_AVAIL+=("$(( avail * 1024 ))")
        DISK_USE_PCT+=("${pct%\%}")

    done < <(LC_ALL=C df -P -k -T -x tmpfs -x devtmpfs -x overlay -x squashfs 2>/dev/null)

}

disk_collect() {

    sw_require_command df || return 127

    disk_discover

}

disk_analyze() {

    local i
    local pct
    local key

    for (( i=0; i<${#DISK_KEYS[@]}; i++ ))
    do

        pct="${DISK_USE_PCT[$i]}"
        key="${DISK_KEYS[$i]}"

        DISK_STATUS[$i]="${SW_STATUS_OK}"

        if (( pct >= DISK_CRITICAL )) &&
           sw_csv_all_above "${key}" used_pct "${DISK_CRITICAL}" "${DISK_SUSTAINED_SAMPLES}"
        then

            DISK_STATUS[$i]="${SW_STATUS_CRITICAL}"

        elif (( pct >= DISK_WARNING )) &&
             sw_csv_all_above "${key}" used_pct "${DISK_WARNING}" "${DISK_SUSTAINED_SAMPLES}"
        then

            DISK_STATUS[$i]="${SW_STATUS_WARNING}"

        fi

    done

}

disk_update_state() {

    local i
    local key

    for (( i=0; i<${#DISK_KEYS[@]}; i++ )); do

        key="${DISK_KEYS[$i]}"

        sw_state_use "${key}"
        sw_state_load

        sw_status_update "${DISK_STATUS[$i]}" "${key}" || continue

        sw_state_set "module_version" "${MODULE_VERSION}"

        sw_state_set "module.label" "${DISK_MOUNTPOINT[$i]}"
        sw_state_set "module.icon" "lucide/hard-drive"
        sw_state_set "module.order" "$MODULE_ORDER"

        # Hidden marker: lets other modules (e.g. du.sh) find disk.sh's
        # own state files unambiguously and read the real mountpoint
        # path without having to parse module.label.
        sw_state_set "_internal.mountpoint" "${DISK_MOUNTPOINT[$i]}"

        sw_state_set "fstype" "${DISK_FSTYPE[$i]}"
        sw_state_set "fstype.label" "Tipo"
        sw_state_set "fstype.order" "10"

        sw_state_set "used_pct" "${DISK_USE_PCT[$i]}"
        sw_state_set "used_pct.label" "Uso"
        sw_state_set "used_pct.widget" "gauge"
        sw_state_set "used_pct.unit" "%"
        sw_state_set "used_pct.warning" "${DISK_WARNING}"
        sw_state_set "used_pct.critical" "${DISK_CRITICAL}"
        sw_state_set "used_pct.order" "50"

        sw_state_set "total" "${DISK_TOTAL[$i]}"
        sw_state_set "total.label" "Total"
        sw_state_set "total.render" "bytes"
        sw_state_set "total.order" "20"

        sw_state_set "used" "${DISK_USED[$i]}"
        sw_state_set "used.label" "Usado"
        sw_state_set "used.render" "bytes"
        sw_state_set "used.order" "30"

        sw_state_set "avail" "${DISK_AVAIL[$i]}"
        sw_state_set "avail.label" "Disponible"
        sw_state_set "avail.render" "bytes"
        sw_state_set "avail.order" "40"

        if [[ "${DISK_MOUNTPOINT[$i]}" == /media* ]]; then
            echo "$(date) (disk_update_state) se genera un timer para ${key}" >> ~/scripts/syswatch/timer.txt
            sw_state_set "info" "Esta ficha se eliminará un tiempo después de extraer el medio"
            sw_state_set "info.order" "60"
            sw_timer_create "${key}" "10" "deletestate"
        fi

        sw_state_save

        sw_csv_append \
            "${key}" \
            "used_pct" \
            "${DISK_USE_PCT[$i]}"

    done

}

disk_report() {

    local i
    local summary=""

    for (( i=0; i<${#DISK_KEYS[@]}; i++ )); do

        summary+="${DISK_MOUNTPOINT[$i]}=${DISK_USE_PCT[$i]}% (${DISK_STATUS[$i]}) "

    done

    sw_log_info \
        "${MODULE_NAME}" \
        "Disk: ${#DISK_KEYS[@]} mount(s): ${summary}"

}

sw_module_run() {

    disk_collect || return 1

    disk_analyze

    disk_update_state

    disk_report

}
