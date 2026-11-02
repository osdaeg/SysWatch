
#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Deleted-open files collector
#
# Collects deleted regular files still held open by processes.
# Does not modify processes or file descriptors.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Load SysWatch libraries
# -----------------------------------------------------------------------------

HELPER_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd -- "${HELPER_DIR}/.." && pwd -P)"

source "${PROJECT_ROOT}/lib/common.sh"

# common.sh enables strict error handling. The collector was designed
# to handle errors explicitly, so preserve its original shell options.
set +o errexit
set +o pipefail
set -u

source "${LIB_DIR}/logger.sh"

# This helper logs locally but must not send individual diagnostics
# to InterCom.
INTERCOM_ENABLE=false
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

DELETED_OPEN_DETAIL_LIMIT=${DELETED_OPEN_DETAIL_LIMIT:-10}
DELETED_OPEN_TIMEOUT_SECONDS=${DELETED_OPEN_TIMEOUT_SECONDS:-30}

DELETED_OPEN_TMPDIR=""

# -----------------------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------------------

deleted_open_log_info() {
    sw_log_info "DeletedOpen" "$1"
    printf 'INFO: %s\n' "$1"
}

deleted_open_log_warning() {
    sw_log_warning "DeletedOpen" "$1"
    printf 'WARNING: %s\n' "$1" >&2
}

deleted_open_log_error() {
    sw_log_error "DeletedOpen" "$1"
    printf 'ERROR: %s\n' "$1" >&2
}

deleted_open_cleanup() {
    if [[ -n "$DELETED_OPEN_TMPDIR" ]]; then
        rm -rf -- "$DELETED_OPEN_TMPDIR"
        DELETED_OPEN_TMPDIR=""
    fi
}

trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
trap 'deleted_open_cleanup' EXIT

# -----------------------------------------------------------------------------
# Collector
# -----------------------------------------------------------------------------

deleted_open_collect() {

    local output_dir="${1:-}"

    local tmpdir
    local lsof_status
    local field
    local pid=""
    local comm=""
    local uid=""
    local fd=""
    local type=""
    local name=""
    local lsof_dev=""
    local lsof_inode=""
    local dev_from_lsof=""
    local fd_num
    local fd_path
    local dev
    local inode
    local logical
    local blocks
    local block_size
    local physical
    local fs_type
    local file_key
    local process_file_key
    local name_display
    local comm_display
    local stat_data

    local total_files=0
    local total_logical=0
    local total_physical=0
    local total_processes=0

    local stat_errors=0
    local race_skips=0
    local identity_errors=0
    local warning_errors=0

    local ignored_warnings=0

    local -A files_logical=()
    local -A files_physical=()
    local -A files_name=()
    local -A files_pids=()
    local -A files_fs=()

    local -A process_name=()
    local -A process_uid=()
    local -A process_files=()
    local -A process_logical=()
    local -A process_physical=()

    local -A process_file_seen=()

    if [[ ! "$DELETED_OPEN_DETAIL_LIMIT" =~ ^[0-9]+$ ]]; then
        deleted_open_log_error "DELETED_OPEN_DETAIL_LIMIT inválido."
        return 1
    fi

    if [[ -z "$output_dir" || ! -d "$output_dir" || ! -w "$output_dir" ]]; then
        deleted_open_log_error "Directorio de salida inválido."
        return 1
    fi

    tmpdir=$(mktemp -d) || {
        deleted_open_log_error "No se pudo crear el directorio temporal."
        return 1
    }

    DELETED_OPEN_TMPDIR="$tmpdir"

    deleted_open_check_lsof_warnings() {

        local line
        local warning_fs
        local warning_path
        local pending_incomplete=0

        while IFS= read -r line || [[ -n "$line" ]]; do

            [[ -n "$line" ]] || continue

            if [[ "$line" =~ ^[[:space:]]+Output\ information\ may\ be\ incomplete\.$ ]] &&
               (( pending_incomplete )); then
                pending_incomplete=0
                continue
            fi

            pending_incomplete=0

            if [[ "$line" =~ ^lsof:\ WARNING:\ can\'t\ stat\(\)\ ([^[:space:]]+)\ file\ system\ (.+)$ ]]; then

                warning_path="${BASH_REMATCH[2]}"

                if ! warning_fs=$(findmnt -T "$warning_path" -n -o FSTYPE 2>/dev/null); then
                    deleted_open_log_error "No se pudo identificar el filesystem de: ${warning_path}"
                    ((warning_errors += 1))
                    continue
                fi

                if [[ -z "$warning_fs" || "$warning_fs" == *$'\n'* ]]; then
                    deleted_open_log_error "Identificación ambigua del filesystem: ${warning_path}"
                    ((warning_errors += 1))
                    continue
                fi

                case "${warning_fs,,}" in
                    fuse.portal|tmpfs|ramfs|overlay|overlayfs|nsfs|nfs|nfs4|cifs|smb3)
                        ((ignored_warnings += 1))
                       ;;
                    ext2/ext3|ext2|ext3|ext4|xfs|btrfs|vfat|exfat|fuseblk|ntfs|ntfs3)
                        deleted_open_log_error "lsof no pudo inspeccionar un filesystem incluido: ${warning_path} (${warning_fs})"
                        ((warning_errors += 1))
                        ;;
                    *)
                        deleted_open_log_warning "Filesystem desconocido en advertencia de lsof: ${warning_path} (${warning_fs})"
                        ((warning_errors += 1))
                        ;;
                esac

                pending_incomplete=1
                continue
            fi

            deleted_open_log_error "Mensaje no reconocido de lsof: ${line}"
            ((warning_errors += 1))

        done < "${tmpdir}/lsof.err"
    }

    if lsof -nP -F0pcuftDinsn +L1 \
        > "${tmpdir}/lsof.out" \
        2> "${tmpdir}/lsof.err"; then
        lsof_status=0
    else
        lsof_status=$?
    fi

    deleted_open_check_lsof_warnings

    if (( lsof_status != 0 )); then
        deleted_open_log_error "lsof devolvió código ${lsof_status}"
        cat "${tmpdir}/lsof.err" >&2
        return 1
    fi

    deleted_open_flush() {

        [[ -n "$pid" && -n "$fd" && "$type" == "REG" ]] ||
            return 0

        [[ "$name" == memfd:* || "$name" == /memfd:* ]] &&
            return 0

        [[ "$fd" =~ ^([0-9]+)[rwu]?$ ]] || return 0
        fd_num="${BASH_REMATCH[1]}"

        fd_path="/proc/${pid}/fd/${fd_num}"

        if [[ ! "$lsof_dev" =~ ^0[xX][[:xdigit:]]+$ ]] ||
           [[ ! "$lsof_inode" =~ ^[0-9]+$ ]]; then
            deleted_open_log_error "Identidad incompleta o inválida en lsof: PID=${pid} FD=${fd_num}"
            ((identity_errors += 1))
            return 0
        fi

        dev_from_lsof=$((16#${lsof_dev:2}))

        if ! fs_type=$(stat -f -L -c '%T' -- "$fd_path" 2>/dev/null); then

            if [[ ! -d "/proc/${pid}" ]] ||
               [[ ! -L "/proc/${pid}/fd/${fd_num}" ]]; then
                ((race_skips += 1))
                return 0
            fi

            deleted_open_log_error "No se pudo identificar filesystem: ${fd_path}"
            ((stat_errors += 1))
            return 0
        fi

        case "${fs_type,,}" in
            ext2/ext3|ext2|ext3|ext4|xfs|btrfs|vfat|exfat|fuseblk|ntfs|ntfs3)
                ;;
            *)
                return 0
                ;;
        esac

        if ! stat_data=$(stat -L -c '%d %i %s %b %B' -- "$fd_path" 2>/dev/null); then

            if [[ ! -d "/proc/${pid}" ]] ||
               [[ ! -L "/proc/${pid}/fd/${fd_num}" ]]; then
                ((race_skips += 1))
                return 0
            fi

            deleted_open_log_error "No se pudo medir archivo: ${fd_path}"
            ((stat_errors += 1))
            return 0
        fi

        if ! read -r dev inode logical blocks block_size <<< "$stat_data"; then
            deleted_open_log_error "Respuesta inválida de stat: ${fd_path}"
            ((stat_errors += 1))
            return 0
        fi

        if [[ ! "$dev" =~ ^[0-9]+$ ]] ||
           [[ ! "$inode" =~ ^[0-9]+$ ]] ||
           [[ ! "$logical" =~ ^[0-9]+$ ]] ||
           [[ ! "$blocks" =~ ^[0-9]+$ ]] ||
           [[ ! "$block_size" =~ ^[0-9]+$ ]] ||
           (( block_size == 0 )); then

            deleted_open_log_error "Datos inválidos de stat: ${fd_path}"
            ((stat_errors += 1))
            return 0
        fi

        if [[ "$dev" != "$dev_from_lsof" ]] ||
           [[ "$inode" != "$lsof_inode" ]]; then
            ((race_skips += 1))
            return 0
        fi

        physical=$((blocks * block_size))
        file_key="${dev}:${inode}"

        if [[ -z ${files_physical[$file_key]+x} ]]; then

            files_logical["$file_key"]=$logical
            files_physical["$file_key"]=$physical
            files_name["$file_key"]=$name
            files_pids["$file_key"]=""
            files_fs["$file_key"]="${fs_type,,}"

            ((total_files += 1))
            ((total_logical += logical))
            ((total_physical += physical))
        fi

        if [[ -z ${process_files[$pid]+x} ]]; then

            process_name["$pid"]=$comm
            process_uid["$pid"]=$uid
            process_files["$pid"]=0
            process_logical["$pid"]=0
            process_physical["$pid"]=0

            ((total_processes += 1))
        fi

        process_file_key="${pid}|${file_key}"

        if [[ -z ${process_file_seen[$process_file_key]+x} ]]; then

            process_file_seen["$process_file_key"]=1

            ((process_files[$pid] += 1))
            ((process_logical[$pid] += logical))
            ((process_physical[$pid] += physical))

            case " ${files_pids[$file_key]} " in
                *" ${pid} "*) ;;
                *)
                    files_pids["$file_key"]+="${pid} "
                    ;;
            esac
        fi
    }

    while IFS= read -r -d '' field; do

        while [[ "$field" == $'\n'* ]]; do
            field="${field#$'\n'}"
        done

        [[ -n "$field" ]] || continue

        case "${field:0:1}" in
            p)
                deleted_open_flush
                pid="${field:1}"
                fd=""
                type=""
                name=""
                lsof_dev=""
                lsof_inode=""
                ;;
            c)
                comm="${field:1}"
                ;;
            u)
                uid="${field:1}"
                ;;
            f)
                deleted_open_flush
                fd="${field:1}"
                type=""
                name=""
                lsof_dev=""
                lsof_inode=""
                ;;
            t)
                type="${field:1}"
                ;;
            D)
                lsof_dev="${field:1}"
                ;;
            i)
                lsof_inode="${field:1}"
                ;;
            n)
                name="${field:1}"
                ;;
        esac

    done < "${tmpdir}/lsof.out"

    deleted_open_flush

    # -------------------------------------------------------------------------
    # Generate structured results.
    # -------------------------------------------------------------------------

    : > "${tmpdir}/details.tsv"
    : > "${tmpdir}/processes.tsv"

    for file_key in "${!files_physical[@]}"; do

        printf -v name_display '%q' "${files_name[$file_key]}"

        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "${files_physical[$file_key]}" \
            "${files_logical[$file_key]}" \
            "$file_key" \
            "${files_pids[$file_key]}" \
            "${files_fs[$file_key]}" \
            "$name_display" >> "${tmpdir}/details.tsv"
    done

    for pid in "${!process_files[@]}"; do

        printf -v comm_display '%q' "${process_name[$pid]}"

        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "${process_physical[$pid]}" \
            "${process_logical[$pid]}" \
            "$pid" \
            "${process_uid[$pid]}" \
            "$comm_display" \
            "${process_files[$pid]}" >> "${tmpdir}/processes.tsv"
    done

    if ! sort -t $'\t' -k1,1nr \
        "${tmpdir}/details.tsv" > "${tmpdir}/details.sorted"; then
        deleted_open_log_error "No se pudo ordenar el detalle."
        return 1
    fi

    if ! sort -t $'\t' -k1,1nr \
        "${tmpdir}/processes.tsv" > "${tmpdir}/processes.sorted"; then
        deleted_open_log_error "No se pudo ordenar el desglose por proceso."
        return 1
    fi

    printf '%s\t%s\t%s\t%s\n' \
        "$total_files" \
        "$total_processes" \
        "$total_logical" \
        "$total_physical" > "${tmpdir}/summary.tsv"

    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$stat_errors" \
        "$identity_errors" \
        "$race_skips" \
        "$warning_errors" \
        "$ignored_warnings" > "${tmpdir}/diagnostics.tsv"    

    # Publish results only after successful generation.
    mv -- "${tmpdir}/summary.tsv" "${output_dir}/summary.tsv" || return 1
    mv -- "${tmpdir}/diagnostics.tsv" "${output_dir}/diagnostics.tsv" || return 1
    mv -- "${tmpdir}/processes.sorted" "${output_dir}/processes.tsv" || return 1
    mv -- "${tmpdir}/details.sorted" "${output_dir}/details.tsv" || return 1

    printf 'Archivos únicos: %s\n' "$total_files"
    printf 'Procesos involucrados: %s\n' "$total_processes"
    printf 'Tamaño lógico: %s bytes\n' "$total_logical"
    printf 'Espacio físico: %s bytes\n' "$total_physical"

    printf 'Errores de stat: %s\n' "$stat_errors"
    printf 'Errores de identidad: %s\n' "$identity_errors"
    printf 'Descriptores desaparecidos: %s\n' "$race_skips"
    printf 'Advertencias invalidantes: %s\n' "$warning_errors"
    printf 'Advertencias ignoradas: %s\n' "$ignored_warnings"

    deleted_open_cleanup

    (( stat_errors == 0 &&
       identity_errors == 0 &&
       warning_errors == 0 ))
}

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

if ! command -v lsof >/dev/null 2>&1; then
    deleted_open_log_error "lsof no está instalado."
    exit 1
fi

if ! command -v findmnt >/dev/null 2>&1; then
    deleted_open_log_error "findmnt no está instalado."
    exit 1
fi

if ! command -v stat >/dev/null 2>&1; then
    deleted_open_log_error "stat no está instalado."
    exit 1
fi

# -----------------------------------------------------------------------------
# Worker
# -----------------------------------------------------------------------------

if [[ "${1:-}" == "--worker" ]]; then
    deleted_open_collect "${2:-}"
    exit $?
fi

# -----------------------------------------------------------------------------
# Wrapper
# -----------------------------------------------------------------------------

output_dir="${1:-}"

if [[ -z "$output_dir" || ! -d "$output_dir" || ! -w "$output_dir" ]]; then
    deleted_open_log_error "Directorio de salida inválido."
    exit 1
fi

if [[ ! "$DELETED_OPEN_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
    deleted_open_log_error "DELETED_OPEN_TIMEOUT_SECONDS inválido."
    exit 1
fi

if ! command -v timeout >/dev/null 2>&1; then
    deleted_open_log_error "timeout no está instalado."
    exit 1
fi

timeout \
    --signal=TERM \
    --kill-after=2s \
    "${DELETED_OPEN_TIMEOUT_SECONDS}s" \
    "$BASH" "$0" --worker "$output_dir"

timeout_status=$?

if (( timeout_status == 124 || timeout_status == 137 )); then
    deleted_open_log_error "La recolección superó el timeout de ${DELETED_OPEN_TIMEOUT_SECONDS} segundos."
    exit 1
fi

exit "$timeout_status"
