#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# rclone FUSE mount health monitoring
#
# Deliberately separate from disk.sh: a broken rclone mount doesn't look
# like a full disk, it looks like a hung stat() call or ENOTCONN. disk.sh
# actively excludes fuse.* mounts (DISK_EXCLUDE_FUSE) precisely because
# this is a different kind of check.
#
# Discovery uses /proc/mounts (kernel mount table metadata) rather than
# `df`, because `df` itself can hang forever on a dead FUSE mount -- which
# is exactly the failure mode this module needs to detect. Each mount is
# then probed individually with its own bounded timeout, so one hung mount
# can't block the check for the others.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Rclone"
readonly MODULE_DESCRIPTION="rclone FUSE mount health monitoring"
readonly MODULE_VERSION="0.1.0"
readonly MODULE_INTERVAL=240

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# Prefix match against the fstype column in /proc/mounts.
readonly RCLONE_FSTYPE_PATTERN="${RCLONE_FSTYPE_PATTERN:-fuse.rclone}"

# How long to wait on a single mount's responsiveness check before giving
# up on it (that mount alone, not the whole module run).
readonly RCLONE_TIMEOUT_SECONDS="${RCLONE_TIMEOUT_SECONDS:-5}"

# Prior checks (besides the current one) that must also have failed before
# flipping to CRITICAL -- a single timeout could just be a slow remote,
# not a genuinely broken mount.
readonly RCLONE_SUSTAINED_SAMPLES="${RCLONE_SUSTAINED_SAMPLES:-3}"

# Overridable for testing; normally always /proc/mounts.
readonly RCLONE_MOUNTS_SOURCE="${RCLONE_MOUNTS_SOURCE:-/proc/mounts}"

# "docker" if rclone runs inside a container, "host" if it's installed
# directly on this machine.
readonly RCLONE_EXECUTABLE="${RCLONE_EXECUTABLE:-host}"
readonly RCLONE_CONTAINER="${RCLONE_CONTAINER:-rclone}"

# By default, the remote name passed to `rclone about` is assumed to be
# the same as the mountpoint's directory name (matches the common
# convention of naming the mount after its remote). When that isn't
# true, map specific directory names to their real remote name here:
# "DirName:realRemoteName,OtherDir:otherRemote".
readonly RCLONE_REMOTE_OVERRIDE="${RCLONE_REMOTE_OVERRIDE:-}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

RCLONE_KEYS=()
RCLONE_MOUNTPOINTS=()
RCLONE_DETAIL=()
RCLONE_FAILED=()
RCLONE_STATUS=()
RCLONE_STATS=()

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

rclone_sanitize_key() {

    local mountpoint="$1"

    local key="${mountpoint#/}"
    key="${key//\//_}"

    printf '%s\n' "${key}"

}

rclone_unescape() {

    # /proc/mounts escapes a few characters octally, most commonly \040
    # for a literal space in a path.
    local path="$1"

    path="${path//\\040/ }"
    path="${path//\\011/	}"

    printf '%s\n' "${path}"

}

rclone_discover() {

    local device
    local mountpoint
    local fstype
    local rest

    RCLONE_KEYS=()
    RCLONE_MOUNTPOINTS=()

    while read -r device mountpoint fstype rest
    do

        case "${fstype}" in

            "${RCLONE_FSTYPE_PATTERN}"*)

                mountpoint="$(rclone_unescape "${mountpoint}")"

                RCLONE_KEYS+=("$(rclone_sanitize_key "${mountpoint}")")
                RCLONE_MOUNTPOINTS+=("${mountpoint}")
                ;;

        esac

    done < "${RCLONE_MOUNTS_SOURCE}"

}

rclone_resolve_remote_name() {

    # Falls back to assuming the mount's directory name IS the remote
    # name (matches the common convention) unless RCLONE_REMOTE_OVERRIDE
    # says otherwise for this specific directory.

    local dir_name="$1"

    if [[ -n "${RCLONE_REMOTE_OVERRIDE}" ]]; then

        local pairs=()
        IFS=',' read -ra pairs <<< "${RCLONE_REMOTE_OVERRIDE}"

        local pair
        local candidate_dir
        local candidate_remote

        for pair in "${pairs[@]}"; do

            candidate_dir="${pair%%:*}"
            candidate_remote="${pair#*:}"

            if [[ "${candidate_dir}" == "${dir_name}" ]]; then

                printf '%s\n' "${candidate_remote}"
                return

            fi

        done

    fi

    printf '%s\n' "${dir_name}"

}

rclone_convert_to_gib() {
    echo "$1" | awk '{
        valor = $1;
        unidad = toupper($2);
        
        # CORRECCIÓN: Validar que sea un número real (entero o decimal) limpio
        if (valor !~ /^[0-9]+(\.[0-9]+)?$/ || valor == "") { print 0; next }
        
        # Convertir según la unidad detectada
        if (unidad ~ /G/)      { multiplicador = 1 }
        else if (unidad ~ /M/) { multiplicador = 1 / 1024 }
        else if (unidad ~ /K/) { multiplicador = 1 / (1024 * 1024) }
        else                   { multiplicador = 1 / (1024 * 1024 * 1024) } # Bytes (B)
        
        printf "%.6f\n", valor * multiplicador
    }'
}

rclone_stats () {

    local mountpoint="$1"
    local remote_name
    remote_name="$(rclone_resolve_remote_name "${mountpoint}")"

    local raw=""
    local salida=""
    local total
    local used 
    local free
    local trashed 
    local other 
    local num_total=0
    local num_used=0
    local percent=0
    local estado

    case "$RCLONE_EXECUTABLE" in
        "docker")
            # Wrapping the assignment in 'if' is what makes this safe
            # under errexit: a plain 'raw=$(...); estado=$?' would abort
            # the whole script on failure before 'estado=$?' ever ran,
            # taking every OTHER mount in this loop down with it.
            if raw=$(docker exec "$RCLONE_CONTAINER" rclone about "${remote_name}:" 2>/dev/null); then
                estado=0
            else
                estado=$?
            fi
            ;;
        "host")
            if raw=$(rclone about "${remote_name}:" 2>/dev/null); then
                estado=0
            else
                estado=$?
            fi
            ;;
        *)
            #echo "Error: Modo RCLONE_MODE '$RCLONE_EXECUTABLE' no válido. Use 'docker' o 'host'."
            estado=1
            raw=""
            ;;
    esac

    if [ $estado -ne 0 ] || [ -z "$raw" ]; then
        RCLONE_STATS=(0 0 0 0 0 0)
    else
        salida=$(echo "$raw" | grep -E '^(Total|Used|Free|Trashed|Other):')

        total=$(echo "$salida" | awk '/Total:/ {print $2" "$3}')
        used=$(echo "$salida" | awk '/Used:/ {print $2" "$3}')
        free=$(echo "$salida" | awk '/Free:/ {print $2" "$3}')
        trashed=$(echo "$salida" | awk '/Trashed:/ {print $2" "$3}')
        other=$(echo "$salida" | awk '/Other:/ {print $2" "$3}')
        
        total1=$(rclone_convert_to_gib "$total")
        used1=$(rclone_convert_to_gib "$used")
        free1=$(rclone_convert_to_gib "$free")
        trashed1=$(rclone_convert_to_gib "$trashed")
        other1=$(rclone_convert_to_gib "$other")

        num_total=$(echo "${total1}" | awk '{print $1}')

        val_used=$(echo "${used1}" | awk '{print $1}')
        val_trashed=$(echo "${trashed1}" | awk '{print ($1 ~ /^[0-9.]/ ? $1 : 0)}')
        val_other=$(echo "${other1}" | awk '{print ($1 ~ /^[0-9.]/ ? $1 : 0)}')

        num_used=$(awk "BEGIN {print $val_used + $val_trashed + $val_other}")

        if [ "$num_total" != "0" ] && [ "$num_used" != "0" ]; then
            percent=$(awk "BEGIN {printf \"%.2f\", ($num_used / $num_total) * 100}")
        fi

        RCLONE_STATS=(
            "${percent:-0}"
            "${total:-0}"
            "${used:-0}"
            "${free:-0}"
            "${trashed:-0}"
            "${other:-0}"
        )
    fi

}

rclone_check_mount() {

    # Sets RCLONE_DETAIL[i] and RCLONE_FAILED[i] for a single mountpoint,
    # bounded by RCLONE_TIMEOUT_SECONDS so a hung mount can only ever cost
    # us that much time, never more.

    local i="$1"
    local mountpoint="$2"

    local rc

    timeout "${RCLONE_TIMEOUT_SECONDS}" stat "${mountpoint}" >/dev/null 2>&1
    rc=$?

    if (( rc == 0 )); then

        RCLONE_DETAIL[$i]="ok"
        RCLONE_FAILED[$i]=0

    elif (( rc == 124 )); then

        RCLONE_DETAIL[$i]="timeout"
        RCLONE_FAILED[$i]=1

    else

        RCLONE_DETAIL[$i]="disconnected"
        RCLONE_FAILED[$i]=1

    fi

}

rclone_collect() {

    sw_require_command timeout || return 127
    sw_require_command stat || return 127

    [[ -r "${RCLONE_MOUNTS_SOURCE}" ]] || {

        sw_log_warning \
            "${MODULE_NAME}" \
            "Cannot read ${RCLONE_MOUNTS_SOURCE}"

        return 1

    }

    rclone_discover

    local i

    for (( i=0; i<${#RCLONE_KEYS[@]}; i++ )); do

        rclone_check_mount "${i}" "${RCLONE_MOUNTPOINTS[$i]}"

    done

}

rclone_analyze() {

    local i
    local key

    for (( i=0; i<${#RCLONE_KEYS[@]}; i++ ))
    do

        key="${RCLONE_KEYS[$i]}"

        RCLONE_STATUS[$i]="${SW_STATUS_OK}"

        if (( RCLONE_FAILED[$i] == 1 )) &&
           sw_csv_all_above "${key}" failed 1 "${RCLONE_SUSTAINED_SAMPLES}"
        then

            RCLONE_STATUS[$i]="${SW_STATUS_CRITICAL}"

        fi

    done

}

rclone_update_state() {

    local i
    local key
    local mountpoint
    local order=20
    local label
    local labels=("% usado" "Total" "Usado" "Libre" "Papelera" "Otros")
    local valor

    for (( i=0; i<${#RCLONE_KEYS[@]}; i++ )); do

        key="${RCLONE_KEYS[$i]}"

        sw_state_use "${key}"
        sw_state_load

        sw_status_update "${RCLONE_STATUS[$i]}" "${key}" || continue

        sw_state_set "module_version" "${MODULE_VERSION}"
        
        mountpoint=$(basename "${RCLONE_MOUNTPOINTS[$i]}")

        sw_state_set "module.label" "rclone: ${mountpoint}"
        sw_state_set "module.icon" "lucide/cloud"
        sw_state_set "module.order" "41"

        sw_state_set "detail" "${RCLONE_DETAIL[$i]}"
        sw_state_set "detail.label" "Estado"
        sw_state_set "detail.order" "10"
        
        RCLONE_STATS=()
        
        rclone_stats "${mountpoint}"
        
        order=20

       # Ciclo para recorrer el array por sus índices (del 0 al 4)
       for j in "${!RCLONE_STATS[@]}"; do
            valor="${RCLONE_STATS[$j]}"
    
            # Si el valor es estrictamente "0", no hace nada y continúa
            if [ "$valor" = "0" ]; then
                continue
            fi
    
            # Obtener la etiqueta correspondiente al índice actual
            label="${labels[$j]}"

            sw_state_set "${label}" "${RCLONE_STATS[$j]}"
            sw_state_set "${label}.label" "${label}"
            

            if [ "${label}" == "% usado" ] 2>/dev/null; then
                sw_state_set "${label}.widget" "gauge"
                sw_state_set "${label}.unit" "%"
                sw_state_set "${label}.order" "70"
            else    
                sw_state_set "${label}.order" "${order}"
                order=$((order + 10))
            fi

        done


        sw_state_save

        sw_csv_append \
            "${key}" \
            "failed" \
            "${RCLONE_FAILED[$i]}"

    done

}

rclone_report() {

    local i
    local summary=""

    for (( i=0; i<${#RCLONE_KEYS[@]}; i++ )); do

        summary+="${RCLONE_MOUNTPOINTS[$i]}=${RCLONE_DETAIL[$i]} "

    done

    sw_log_info \
        "${MODULE_NAME}" \
        "Rclone: ${#RCLONE_KEYS[@]} mount(s): ${summary}"

}

sw_module_run() {

    rclone_collect || return 1

    rclone_analyze

    rclone_update_state

    rclone_report

}
