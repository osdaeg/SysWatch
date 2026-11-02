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
readonly MODULE_SCRIPT="$(realpath "${BASH_SOURCE[0]}")"
readonly MODULE_DESCRIPTION="Disk usage monitoring"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_INTERVAL_NORMAL=${MODULE_INTERVAL_NORMAL:-}
MODULE_INTERVAL_ALT=${MODULE_INTERVAL_ALT:-}
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

readonly DISK_INODE_WARNING="${DISK_INODE_WARNING:-85}"
readonly DISK_INODE_CRITICAL="${DISK_INODE_CRITICAL:-95}"
readonly DISK_INODE_SUSTAINED_SAMPLES="${DISK_INODE_SUSTAINED_SAMPLES:-3}"

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

DISK_INODE_TOTAL=()
DISK_INODE_USED=()
DISK_INODE_AVAIL=()
DISK_INODE_USE_PCT=()

DISK_SOURCE=()
DISK_CLASS=()

declare -gA MOUNTS=()

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

disk_mounts_load() {
    unset MOUNTS
    declare -gA MOUNTS=()

    #local file="${PROJECT_DIR}/config/mounts.conf"

    #[[ -f "${file}" ]] || return 0

    #source "${file}" || return 1

    sw_module_load_config "mounts"

}

disk_mount_timer_exists() {
    local key="$1"

    [[ -f "${SW_TIMER_FILE}" ]] || return 1

    awk -F= -v key="${key}" \
        '$1 == key { found=1; exit }
         END { exit !found }' "${SW_TIMER_FILE}"
}

disk_mounts_sync() {
    local key
    local mountpoint
    local content
    local quoted
    local state_file
    local -A previous=()
    local -A current=()

    # Conservar el inventario anterior.
    for key in "${!MOUNTS[@]}"; do
        previous["${key}"]="${MOUNTS[$key]}"
    done

    # Construir el inventario actual.
    for i in "${!DISK_KEYS[@]}"; do
        key="${DISK_KEYS[$i]}"
        mountpoint="${DISK_MOUNTPOINT[$i]}"

        current["${key}"]="${mountpoint}"

        # Si reapareció, cancelar su timer pendiente.
        SW_TIMER_MODULE="${key}"
        sw_timer_delete
    done

    # Buscar montajes registrados que ya no están presentes.
    for key in "${!previous[@]}"; do

        if [[ ${current[$key]+_} ]]; then
            continue
        fi

        state_file="${STATE_DIR}/${key}.state"

        # Si la ficha ya fue eliminada, retirar el registro.
        if [[ ! -f "${state_file}" ]]; then
            continue
        fi

        # Crear el timer una sola vez.
        if ! disk_mount_timer_exists "${key}"; then
            sw_timer_create "${key}" "2" "deletestate" || return 1
        fi

        # Mantener la entrada mientras exista la ficha.
        current["${key}"]="${previous[$key]}"
    done

    # Guardar el inventario actualizado.
    content="declare -gA MOUNTS=("

    for key in "${!current[@]}"; do
        content+=$'\n'"[\"${key}\"]=\"${current[$key]}\""
    done

    content+=$'\n'")"

    # Reconstruir también el array global.
    MOUNTS=()
    for key in "${!current[@]}"; do
        MOUNTS["${key}"]="${current[$key]}"
    done

    sw_module_save_config "mounts" "${content}"
}

disk_sanitize_key() {
    local path="$1"

    [[ "${path}" == "/" ]] && {
        printf 'root'
        return
    }

    path="${path#/}"
    path="${path//_/__}"
    path="${path//\//_}"

    printf '%s\n' "${path}"
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

    local fs
    local fstype
    local blocks
    local used
    local avail
    local pct
    local mountpoint
    local inode_total
    local inode_used
    local inode_avail
    local inode_pct
    local inode_key
    local i
    local blktype

    local source
    local device_path
    local device_type
    local rm
    local tran
    local physical_disks
    local classification

    local -a inode_keys=()
    local -a inode_totals=()
    local -a inode_used_values=()
    local -a inode_avail_values=()
    local -a inode_pct_values=()

    local network_fs
    local network_type

    local btrfs_type
    local btrfs_fsroot

    local root_source
    local root_device
    local mount_device

    root_source="$(findmnt -rn -M / -o SOURCE 2>/dev/null)"
    root_device="${root_source%%\[*}"

    DISK_KEYS=()
    DISK_MOUNTPOINT=()
    DISK_FSTYPE=()
    DISK_TOTAL=()
    DISK_USED=()
    DISK_AVAIL=()
    DISK_USE_PCT=()
    DISK_INODE_TOTAL=()
    DISK_INODE_USED=()
    DISK_INODE_AVAIL=()
    DISK_INODE_USE_PCT=()
    DISK_SOURCE=()
    DISK_CLASS=()

    # Collect inode information first.
    while read -r fs fstype inode_total inode_used inode_avail inode_pct mountpoint; do

        [[ "${fs}" == "Filesystem" ]] && continue
        [[ -z "${mountpoint}" ]] && continue

        inode_pct="${inode_pct%\%}"

        [[ "${inode_total}" =~ ^[0-9]+$ ]] || continue
        [[ "${inode_used}" =~ ^[0-9]+$ ]] || continue
        [[ "${inode_avail}" =~ ^[0-9]+$ ]] || continue
        [[ "${inode_pct}" =~ ^[0-9]+$ ]] || continue
        ((inode_total > 0)) || continue

        inode_keys+=("${fs}|${mountpoint}")
        inode_totals+=("${inode_total}")
        inode_used_values+=("${inode_used}")
        inode_avail_values+=("${inode_avail}")
        inode_pct_values+=("${inode_pct}")

    done < <(LC_ALL=C df -i -P -T 2>/dev/null)

    # Collect disk-space information.
    while read -r fs fstype blocks used avail pct mountpoint; do

        [[ "${fs}" == "Filesystem" ]] && continue

        case "${mountpoint}" in
        /proc* | /sys* | /dev* | /run* | /snap*)
            continue
            ;;
        esac

        [[ -z "${mountpoint}" ]] && continue

        # Exclude Btrfs subvolumes, except root (/).
        if [[ "${DISK_EXCLUDE_BTRFS_SUBVOLUMES:-false}" == "true" &&
            "${fstype}" == "btrfs" &&
            "${mountpoint}" != "/" ]]; then

            mount_device="${fs%%\[*}"

            if [[ -n "${root_device}" &&
                "${mount_device}" == "${root_device}" ]]; then
                continue
            fi
        fi

        # Excluir mounts fuse.*, salvo los tipos permitidos explícitamente
        if [[ "${fstype}" == fuse.* ]]; then
            fuse_type="${fstype#fuse.}"
            fuse_allowed=false

            IFS=',' read -ra fuse_allow_list <<<"${DISK_ALLOW_SPECIFIC_FUSE:-}"

            for allowed_type in "${fuse_allow_list[@]}"; do
                if [[ "${fuse_type}" == "${allowed_type}" ]]; then
                    fuse_allowed=true
                    break
                fi
            done

            if [[ "${DISK_EXCLUDE_FUSE}" == "true" && "${fuse_allowed}" != "true" ]]; then
                continue
            fi
        fi

        disk_is_excluded_mount "${mountpoint}" && continue

        DISK_KEYS+=("$(disk_sanitize_key "${mountpoint}")")
        DISK_MOUNTPOINT+=("${mountpoint}")

        DISK_TOTAL+=("$((blocks * 1024))")
        DISK_USED+=("$((used * 1024))")
        DISK_AVAIL+=("$((avail * 1024))")
        DISK_USE_PCT+=("${pct%\%}")

        DISK_SOURCE+=("${fs}")

        # Classify the filesystem or source device.

        source="${fs}"
        physical_disks=""
        classification="unidentified"

        # Check configured network filesystem types.
        network_fs=",${NETWORK_FS//[[:space:]]/},"

        if [[ "${network_fs,,}" == *",${fstype,,},"* ]]; then
            classification="network"

        # SSHFS: remote filesystem using FUSE.
        elif [[ "${fstype}" == "fuse.sshfs" ]]; then
            classification="network"

        # RCLONE: remote filesystem using FUSE.
        elif [[ "${fstype}" == "fuse.rclone" ]]; then
            classification="network"

        # WebDAV: FUSE mount with an HTTP(S) source.
        elif [[ "${fstype}" == "fuse" && "${source}" =~ ^https?:// ]]; then
            classification="network"

        elif [[ "${source}" == /dev/* ]]; then

            source_type="$(lsblk --noheadings --raw --output TYPE "${source}" 2>/dev/null | head -n 1)"

            if [[ "${fstype}" == "fuseblk" ]]; then
                blktype=$(lsblk -no FSTYPE "${source}")
                if [[ "${blktype}" == "ntfs" ]]; then
                    classification="windows"
                fi
                fstype="$blktype"
            fi

            if [[ "${source_type}" == raid* ]]; then
                classification="raid"
            fi

            while read -r device_path device_type rm tran; do

                [[ "${device_type}" == "disk" ]] || continue
                [[ "${rm}" == "1" || -n "${tran}" ]] || continue

                if [[ -n "${physical_disks}" ]]; then
                    physical_disks+=","
                fi

                physical_disks+="${device_path##*/}"

                if [[ "${rm}" == "1" || "${tran}" == "usb" ]]; then
                    classification="removable"
                elif [[ "${classification}" != "removable" && "${classification}" != "raid" ]]; then
                    classification="local"
                fi

            done < <(
                lsblk --inverse --noheadings --raw \
                    --output PATH,TYPE,RM,TRAN \
                    "${source}" 2>/dev/null
            )

        fi

        #echo "$mountpoint $fstype" >>~/scripts/syswatch/fs.txt

        DISK_CLASS+=("${classification}")
        DISK_FSTYPE+=("${fstype}")

        inode_total=""
        inode_used=""
        inode_avail=""
        inode_pct=""

        inode_key="${fs}|${mountpoint}"

        for ((i = 0; i < ${#inode_keys[@]}; i++)); do

            if [[ "${inode_keys[$i]}" == "${inode_key}" ]]; then
                inode_total="${inode_totals[$i]}"
                inode_used="${inode_used_values[$i]}"
                inode_avail="${inode_avail_values[$i]}"
                inode_pct="${inode_pct_values[$i]}"
                break
            fi

        done

        DISK_INODE_TOTAL+=("${inode_total}")
        DISK_INODE_USED+=("${inode_used}")
        DISK_INODE_AVAIL+=("${inode_avail}")
        DISK_INODE_USE_PCT+=("${inode_pct}")

    done < <(LC_ALL=C df -P -k -T -x tmpfs -x devtmpfs -x overlay -x squashfs 2>/dev/null)

}

disk_report_devices() {

    local i

    for ((i = 0; i < ${#DISK_KEYS[@]}; i++)); do

        printf '%-24s source=%-18s classification=%s\n' \
            "${DISK_MOUNTPOINT[$i]}" \
            "${DISK_SOURCE[$i]}" \
            "${DISK_CLASS[$i]}"

    done
}

disk_collect() {

    sw_require_command df || return 127

    disk_discover
    #disk_report_devices

}

disk_raid_load_config() {
    sw_module_load_config raid
}

disk_raid_check() {

    local array_name="$1"
    local md_path="/sys/block/${array_name}"
    local line
    local found=false
    local active_line=""
    local expected
    local active
    local members

    # Validate the registered array name.
    [[ "${array_name}" =~ ^md[0-9]+$ ]] || {
        printf '%s\n' "${SW_STATUS_UNKNOWN}"
        return
    }

    # The array is not present in sysfs.
    if [[ ! -d "${md_path}/md" ]]; then
        printf '%s\n' "${SW_STATUS_CRITICAL}"
        return
    fi

    # The array is present, but its current state is unknown
    # if /proc/mdstat cannot be read.
    [[ -r /proc/mdstat ]] || {
        printf '%s\n' "${SW_STATUS_UNKNOWN}"
        return
    }

    # Find this array in /proc/mdstat.
    while IFS= read -r line; do

        if [[ "${line}" =~ ^${array_name}[[:space:]]*: ]]; then
            found=true
            active_line="${line}"

            # An assembled but inactive array is not healthy.
            if [[ "${line}" =~ :[[:space:]]+inactive ]]; then
                printf '%s\n' "${SW_STATUS_CRITICAL}"
                return
            fi

            continue
        fi

        if [[ "${found}" == true ]]; then

            # Stop when this array's section ends.
            [[ "${line}" =~ ^[[:space:]] ]] || break

            if [[ "${line}" =~ \[([0-9]+)/([0-9]+)\][[:space:]]+\[([U_]+)\] ]]; then

                expected="${BASH_REMATCH[1]}"
                active="${BASH_REMATCH[2]}"
                members="${BASH_REMATCH[3]}"

                if [[ "${members}" == *"_"* ]] ||
                    ((active < expected)); then
                    printf '%s\n' "${SW_STATUS_WARNING}"
                else
                    printf '%s\n' "${SW_STATUS_OK}"
                fi

                return
            fi

        fi

    done </proc/mdstat

    # Present in sysfs but not represented as an active array
    # in /proc/mdstat: do not report it as healthy.
    printf '%s\n' "${SW_STATUS_CRITICAL}"
}

disk_raid_update_state() {

    local array_name
    local key
    local raid_status
    local varname
    local level
    local devices
    local members

    for array_name in "${RAID_ARRAYS[@]}"; do

        [[ "${array_name}" =~ ^md[0-9]+$ ]] || continue

        key="raid_${array_name}"

        # Check the actual RAID status.
        raid_status="$(disk_raid_check "${array_name}")"
        [[ -n "${raid_status}" ]] || raid_status="${SW_STATUS_UNKNOWN}"

        # Load the independent RAID state.
        sw_state_use "${key}"

        if [[ -n "${MODULE_REMOTE}" ]]; then
            sw_state_remote "${MODULE_REMOTE}"
        fi

        sw_state_load

        # Record status changes through SysWatch's event system.
        sw_status_update "${raid_status}" "${key}" || continue

        # General card information.
        sw_state_set "module.icon" "lucide/layers"
        sw_state_set "module.order" "$MODULE_ORDER"
        sw_state_set "module.label" "RAID ${array_name}"

        # Read metadata from the persistent registry.
        level=""
        devices=""
        members=""

        varname="RAID_${array_name}_LEVEL"
        [[ -v "${varname}" ]] && level="${!varname}"

        varname="RAID_${array_name}_DEVICES"
        [[ -v "${varname}" ]] && devices="${!varname}"

        varname="RAID_${array_name}_MEMBERS"
        [[ -v "${varname}" ]] && members="${!varname}"

        # RAID level.
        sw_state_set "level" "${level}"
        sw_state_set "level.label" "$(sw_translate "RAID level")"
        sw_state_set "level.order" "10"

        # Expected number of devices.
        sw_state_set "devices" "${devices}"
        sw_state_set "devices.label" "$(sw_translate "Expected devices")"
        sw_state_set "devices.order" "20"

        # Registered member devices.
        sw_state_set "members" "${members}"
        sw_state_set "members.label" "$(sw_translate "Member devices")"
        sw_state_set "members.order" "30"

        sw_state_save

    done
}

disk_raid_sync_config() {
    local md_path
    local md_dir
    local md_name
    local uuid
    local level
    local raid_disks
    local degraded
    local slave
    local members
    local old_members
    local varname
    local known
    local found
    local active_count=0
    local config
    local value
    local field
    local quoted
    local -a member_list=()

    # Load the persistent registry.
    disk_raid_load_config || return 1

    # Initialize the registry if necessary.
    declare -p RAID_ARRAYS &>/dev/null || RAID_ARRAYS=()

    # Discover active arrays using sysfs, without mdadm.
    for md_path in /sys/block/md*; do
        [[ -d "${md_path}/md" ]] || continue

        md_name="${md_path##*/}"
        [[ "${md_name}" =~ ^md[0-9]+$ ]] || continue

        md_dir="${md_path}/md"

        [[ -r "${md_dir}/uuid" ]] || continue
        [[ -r "${md_dir}/level" ]] || continue
        [[ -r "${md_dir}/raid_disks" ]] || continue
        [[ -r "${md_dir}/degraded" ]] || continue

        IFS= read -r uuid <"${md_dir}/uuid"
        IFS= read -r level <"${md_dir}/level"
        IFS= read -r raid_disks <"${md_dir}/raid_disks"
        IFS= read -r degraded <"${md_dir}/degraded"

        [[ -n "${uuid}" && -n "${level}" ]] || continue
        [[ "${raid_disks}" =~ ^[0-9]+$ ]] || continue

        ((active_count += 1))

        # Add newly discovered arrays to the registry.
        found=false
        for known in "${RAID_ARRAYS[@]}"; do
            [[ "${known}" == "${md_name}" ]] && found=true
        done

        if [[ "${found}" == false ]]; then
            RAID_ARRAYS+=("${md_name}")
        fi

        # Collect currently attached members.
        member_list=()
        for slave in "${md_path}"/slaves/*; do
            [[ -e "${slave}" ]] || continue
            member_list+=("/dev/${slave##*/}")
        done

        members=""
        if ((${#member_list[@]} > 0)); then
            printf -v members '%s ' "${member_list[@]}"
            members="${members% }"
        fi

        # Preserve the previous member list while degraded.
        varname="RAID_${md_name}_MEMBERS"
        old_members=""

        if [[ -v "${varname}" ]]; then
            old_members="${!varname}"
        fi

        if [[ "${degraded}" != "0" && -n "${old_members}" ]]; then
            members="${old_members}"
        fi

        printf -v "RAID_${md_name}_UUID" '%s' "${uuid}"
        printf -v "RAID_${md_name}_LEVEL" '%s' "${level}"
        printf -v "RAID_${md_name}_DEVICES" '%s' "${raid_disks}"
        printf -v "RAID_${md_name}_MEMBERS" '%s' "${members}"
    done

    # Preserve the registry when all arrays are stopped.
    if ((active_count == 0)); then
        return 0
    fi

    # Build the Bash configuration with safely quoted values.
    config=$'# Generated automatically by SysWatch. Do not edit while running.\n'
    config+='RAID_ARRAYS=('

    for md_name in "${RAID_ARRAYS[@]}"; do
        printf -v quoted '%q' "${md_name}"
        config+=" ${quoted}"
    done

    config+=" )"$'\n'

    # Write all registered arrays, including currently stopped ones.
    for md_name in "${RAID_ARRAYS[@]}"; do
        [[ "${md_name}" =~ ^md[0-9]+$ ]] || continue

        for field in UUID LEVEL DEVICES MEMBERS; do
            varname="RAID_${md_name}_${field}"
            value=""

            if [[ -v "${varname}" ]]; then
                value="${!varname}"
            fi

            printf -v quoted '%q' "${value}"
            config+="${varname}=${quoted}"$'\n'
        done
    done

    sw_module_save_config raid "${config}"
}

disk_raid_status() {
    local device="$1"
    local array_name
    local line
    local found=false
    local active_line=""
    local raid_expected
    local raid_active
    local members

    array_name="${device##*/}"

    [[ -r /proc/mdstat ]] || {
        printf '%s\n' "${SW_STATUS_UNKNOWN}"
        return
    }

    while IFS= read -r line; do
        if [[ "${line}" =~ ^${array_name}[[:space:]]*: ]]; then
            found=true
            active_line="${line}"

            if [[ "${active_line}" =~ :[[:space:]]+inactive ]]; then
                printf '%s\n' "${SW_STATUS_CRITICAL}"
                return
            fi

            continue
        fi

        if [[ "${found}" == true ]]; then
            [[ "${line}" =~ ^[[:space:]] ]] || break

            if [[ "${line}" =~ \[([0-9]+)/([0-9]+)\][[:space:]]+\[([U_]+)\] ]]; then
                raid_expected="${BASH_REMATCH[1]}"
                raid_active="${BASH_REMATCH[2]}"
                members="${BASH_REMATCH[3]}"

                if [[ "${members}" == *"_"* ]] ||
                    ((raid_active < raid_expected)); then
                    printf '%s\n' "${SW_STATUS_WARNING}"
                else
                    printf '%s\n' "${SW_STATUS_OK}"
                fi
                return
            fi
        fi
    done </proc/mdstat

    if [[ ! -e "${device}" ]]; then
        printf '%s\n' "${SW_STATUS_CRITICAL}"
    else
        printf '%s\n' "${SW_STATUS_UNKNOWN}"
    fi
}

disk_analyze() {

    local i
    local pct
    local inode_pct
    local key
    local disk_status
    local inode_status

    local raid_status
    local source

    for ((i = 0; i < ${#DISK_KEYS[@]}; i++)); do

        pct="${DISK_USE_PCT[$i]}"
        inode_pct="${DISK_INODE_USE_PCT[$i]}"
        key="${DISK_KEYS[$i]}"

        disk_status="${SW_STATUS_OK}"
        inode_status="${SW_STATUS_OK}"

        # ---------------------------------------------------------------------
        # Disk space
        # ---------------------------------------------------------------------

        if ((pct >= DISK_CRITICAL)) &&
            sw_csv_all_above \
                "${key}" \
                used_pct \
                "${DISK_CRITICAL}" \
                "${DISK_SUSTAINED_SAMPLES}"; then

            disk_status="${SW_STATUS_CRITICAL}"

        elif ((pct >= DISK_WARNING)) &&
            sw_csv_all_above \
                "${key}" \
                used_pct \
                "${DISK_WARNING}" \
                "${DISK_SUSTAINED_SAMPLES}"; then

            disk_status="${SW_STATUS_WARNING}"

        fi

        # ---------------------------------------------------------------------
        # Inode usage
        # ---------------------------------------------------------------------

        if [[ "${inode_pct}" =~ ^[0-9]+$ ]]; then

            if ((inode_pct >= DISK_INODE_CRITICAL)); then

                inode_status="${SW_STATUS_CRITICAL}"

            elif ((inode_pct >= DISK_INODE_WARNING)) &&
                sw_csv_all_above \
                    "${key}" \
                    inode_used_pct \
                    "${DISK_INODE_WARNING}" \
                    "${DISK_INODE_SUSTAINED_SAMPLES}"; then

                inode_status="${SW_STATUS_WARNING}"

            fi

        fi

        # ---------------------------------------------------------------------
        # Combined status
        # ---------------------------------------------------------------------

        DISK_STATUS[$i]="${SW_STATUS_OK}"

        if [[ "${disk_status}" == "${SW_STATUS_CRITICAL}" ||
            "${inode_status}" == "${SW_STATUS_CRITICAL}" ]]; then

            DISK_STATUS[$i]="${SW_STATUS_CRITICAL}"

        elif [[ "${disk_status}" == "${SW_STATUS_WARNING}" ||
            "${inode_status}" == "${SW_STATUS_WARNING}" ]]; then

            DISK_STATUS[$i]="${SW_STATUS_WARNING}"

        fi

    done

}

disk_update_state() {

    local i
    local key

    for ((i = 0; i < ${#DISK_KEYS[@]}; i++)); do

        key="${DISK_KEYS[$i]}"

        sw_state_use "${key}"

        if [[ -n "$MODULE_REMOTE" ]]; then
            sw_state_remote "$MODULE_REMOTE"
        fi

        sw_state_load

        sw_status_update "${DISK_STATUS[$i]}" "${key}" || continue

        #echo "${DISK_MOUNTPOINT[$i]} Clase: ${DISK_CLASS[$i]}"

        case "${DISK_CLASS[$i]}" in

        removable)
            sw_state_set "module.icon" "lucide/usb"
            ;;
        network)
            sw_state_set "module.icon" "lucide/network"
            ;;
        raid)
            sw_state_set "module.icon" "lucide/layers"
            ;;
        *)
            sw_state_set "module.icon" "lucide/hard-drive"
            ;;
        esac

        sw_state_set "module.order" "$MODULE_ORDER"

        label="${DISK_MOUNTPOINT[$i]}"

        sw_state_set "mountpoint" "${DISK_MOUNTPOINT[$i]}"
        sw_state_set "mountpoint.label" "$(sw_translate "Mountpoint")"
        sw_state_set "mountpoint.hidden" "true"
        sw_state_set "mountpoint.order" "51"

        sw_state_set "source" "${DISK_SOURCE[$i]}"
        sw_state_set "source.label" "$(sw_translate "Source")"
        sw_state_set "source.hidden" "true"
        sw_state_set "source.order" "52"

        if [[ "${DISK_CLASS[$i]}" == "network" ]]; then
            source="${DISK_SOURCE[$i]}"

            case "${DISK_FSTYPE[$i]}" in
            "cifs")
                label="$(sw_translate "SMB mount")"
                ;;

            "nfs" | "nfs4" | "nfsd")
                label="$(sw_translate "NFS mount")"
                ;;

            "fuse.sshfs")
                label="$(sw_translate "SSH mount")"
                ;;

            "fuse.rclone")
                label="$(sw_translate "RCLONE mount")"
                ;;

            "fuse")
                if pgrep -f "mount.davfs.* ${DISK_MOUNTPOINT[$i]}" >/dev/null; then
                    label="$(sw_translate "WebDav mount")"
                else
                    label="$(sw_translate "FUSE mount (unidentified)")"
                fi
                ;;

            "")
                label="$(sw_translate "Unidentified file system")"
                ;;

            *)
                label="$(sw_translate "Another file system") \(${DISK_FSTYPE[$i]}\)"
                ;;
            esac

            sw_state_set "mountpoint.hidden" "false"
            sw_state_set "source.hidden" "false"
        fi

        sw_state_set "module.label" "${label}"

        # Hidden marker: lets other modules (e.g. du.sh) find disk.sh's
        # own state files unambiguously and read the real mountpoint
        # path without having to parse module.label.
        sw_state_set "_internal.mountpoint" "${DISK_MOUNTPOINT[$i]}"

        sw_state_set "fstype" "${DISK_FSTYPE[$i]}"
        sw_state_set "fstype.label" "$(sw_translate "Type")"
        sw_state_set "fstype.order" "10"

        sw_state_set "used_pct" "${DISK_USE_PCT[$i]}"
        sw_state_set "used_pct.label" "$(sw_translate "Used")"
        sw_state_set "used_pct.widget" "gauge"
        sw_state_set "used_pct.unit" "%"
        sw_state_set "used_pct.warning" "${DISK_WARNING}"
        sw_state_set "used_pct.critical" "${DISK_CRITICAL}"
        sw_state_set "used_pct.order" "50"

        # Inode usage

        if [[ "${DISK_INODE_USE_PCT[$i]}" =~ ^[0-9]+$ ]]; then

            if ((DISK_INODE_USE_PCT[i] > DISK_INODE_WARNING)); then

                sw_state_set "inode_used_pct" "${DISK_INODE_USE_PCT[$i]}"
                sw_state_set "inode_used_pct.label" "$(sw_translate "Inodes used")"
                sw_state_set "inode_used_pct.widget" "gauge"
                sw_state_set "inode_used_pct.unit" "%"
                sw_state_set "inode_used_pct.warning" "${DISK_INODE_WARNING}"
                sw_state_set "inode_used_pct.critical" "${DISK_INODE_CRITICAL}"
                sw_state_set "inode_used_pct.order" "55"

                sw_state_set "inode_total" "${DISK_INODE_TOTAL[$i]}"
                sw_state_set "inode_total.label" "$(sw_translate "Total inodes")"
                sw_state_set "inode_total.order" "70"

                sw_state_set "inode_used" "${DISK_INODE_USED[$i]}"
                sw_state_set "inode_used.label" "$(sw_translate "Used inodes")"
                sw_state_set "inode_used.order" "80"

                sw_state_set "inode_avail" "${DISK_INODE_AVAIL[$i]}"
                sw_state_set "inode_avail.label" "$(sw_translate "Available inodes")"
                sw_state_set "inode_avail.order" "90"

            else

                for state_key in \
                    inode_used_pct \
                    inode_total \
                    inode_used \
                    inode_avail; do
                    sw_state_delete_key "${state_key}"
                done

            fi

        else

            # Remove stale inode information when unavailable.
            for state_key in \
                inode_used_pct \
                inode_total \
                inode_used \
                inode_avail; do
                sw_state_delete_key "${state_key}"
            done

        fi

        sw_state_set "total" "${DISK_TOTAL[$i]}"
        sw_state_set "total.label" "$(sw_translate "Total")"
        sw_state_set "total.render" "bytes"
        sw_state_set "total.order" "20"

        sw_state_set "used" "${DISK_USED[$i]}"
        sw_state_set "used.label" "$(sw_translate "Used")"
        sw_state_set "used.render" "bytes"
        sw_state_set "used.order" "30"

        sw_state_set "avail" "${DISK_AVAIL[$i]}"
        sw_state_set "avail.label" "$(sw_translate "Available")"
        sw_state_set "avail.render" "bytes"
        sw_state_set "avail.order" "40"

        if [[ "${DISK_CLASS[$i]}" == "removable" ]]; then
            sw_state_set "info" "$(sw_translate "This card will be removed some time after the media is ejected.")"
            sw_state_set "info.order" "300"
            #sw_timer_create "${key}" "10" "deletestate"
        fi

        sw_state_save

        sw_csv_append \
            "${key}" \
            "used_pct" \
            "${DISK_USE_PCT[$i]}"

        if [[ "${DISK_INODE_USE_PCT[$i]}" =~ ^[0-9]+$ ]]; then

            sw_csv_append \
                "${key}" \
                "inode_used_pct" \
                "${DISK_INODE_USE_PCT[$i]}"

        fi

    done

}

disk_report() {

    local i
    local summary=""

    for ((i = 0; i < ${#DISK_KEYS[@]}; i++)); do

        summary+="${DISK_MOUNTPOINT[$i]}=${DISK_USE_PCT[$i]}% (${DISK_STATUS[$i]}) "

    done

    sw_log_info \
        "${MODULE_NAME}" \
        "Disk: ${#DISK_KEYS[@]} mount(s): ${summary}"

}

sw_module_run() {

    disk_mounts_load || return 1

    disk_raid_sync_config || return 1

    disk_raid_check md0

    disk_collect || return 1

    disk_analyze

    disk_update_state

    disk_mounts_sync || return 1

    disk_raid_update_state

    disk_report

}
