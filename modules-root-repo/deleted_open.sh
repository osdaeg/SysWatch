
#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Deleted-open files module
#
# Detects deleted regular files still held open by processes.
# Reports physical disk space retained and per-process details.
# Does not modify processes or file descriptors.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="DeletedOpen"
readonly MODULE_SCRIPT="$(realpath "${BASH_SOURCE[0]}")"
readonly MODULE_DESCRIPTION="Deleted files still held open by processes"
readonly MODULE_VERSION="0.1.0"

MODULE_INTERVAL=${MODULE_INTERVAL_NORMAL:-300}
MODULE_ORDER=${MODULE_ORDER:-43}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly DELETED_OPEN_WARNING_BYTES="${DELETED_OPEN_WARNING_BYTES:-1073741824}"
readonly DELETED_OPEN_CRITICAL_BYTES="${DELETED_OPEN_CRITICAL_BYTES:-5368709120}"
DELETED_OPEN_DETAIL_LIMIT="${DELETED_OPEN_DETAIL_LIMIT:-10}"
DELETED_OPEN_TIMEOUT_SECONDS="${DELETED_OPEN_TIMEOUT_SECONDS:-30}"

# -----------------------------------------------------------------------------
# State helpers
# -----------------------------------------------------------------------------

deleted_open_state_select() {

    local state_name="$1"

    sw_state_use "$state_name"

    # sw_state_remote() does not reset these variables when the
    # configured remote directory does not exist.
    SW_STATE_REMOTE=false
    SW_STATE_REMOTE_DIR=""
    SW_STATE_REMOTE_FILE=""

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE" || true
    fi
}

deleted_open_remove_detail() {

    deleted_open_state_select "deleted_open_detail"
    sw_state_delete
}

deleted_open_unknown() {

    local reason="$1"

    deleted_open_state_select "deleted_open"

    sw_state_load

    sw_status_update "UNKNOWN" "$reason" || true

    sw_state_set "module_version" "$MODULE_VERSION"
    sw_state_set "module.label" "Deleted Open"
    sw_state_set "module.icon" "lucide/file-x"
    sw_state_set "module.order" "$MODULE_ORDER"

    sw_state_set "error" "$reason"
    sw_state_set "error.label" "$(sw_translate "Error")"
    sw_state_set "error.order" "100"

    # Remove results from the previous successful measurement.
    for key in \
        files processes logical physical \
        stat_errors identity_errors race_skips \
        warning_errors ignored_warnings; do
        sw_state_delete_key "$key"
    done

    sw_state_delete_prefix "process_"

    sw_state_save

    deleted_open_remove_detail

    sw_log_warning "$MODULE_NAME" "$reason"

    return 0
}

# -----------------------------------------------------------------------------
# Configuration validation
# -----------------------------------------------------------------------------

deleted_open_validate_config() {

    local value

    for value in \
        "$DELETED_OPEN_WARNING_BYTES" \
        "$DELETED_OPEN_CRITICAL_BYTES" \
        "$DELETED_OPEN_DETAIL_LIMIT" \
        "$DELETED_OPEN_TIMEOUT_SECONDS"; do

        [[ "$value" =~ ^[0-9]+$ ]] || return 1

    done

    (( DELETED_OPEN_WARNING_BYTES > 0 )) || return 1
    (( DELETED_OPEN_CRITICAL_BYTES > DELETED_OPEN_WARNING_BYTES )) || return 1
    (( DELETED_OPEN_TIMEOUT_SECONDS > 0 )) || return 1

    return 0
}

# -----------------------------------------------------------------------------
# Module
# -----------------------------------------------------------------------------

sw_module_run() {

    local output_dir=""
    local helper="${HELPERS_DIR}/deleted_open_collect.sh"
    local helper_status

    local total_files
    local total_processes
    local total_logical
    local total_physical

    local stat_errors
    local identity_errors
    local race_skips
    local warning_errors
    local ignored_warnings

    local extra

    local status
    local reason

    local physical
    local logical
    local pid
    local uid
    local comm
    local process_files

    local dev_inode
    local pids
    local fs_type
    local filename

    local rank
    local order

    local key

    # -------------------------------------------------------------------------
    # Dependencies and configuration.
    # -------------------------------------------------------------------------

    if [[ ! -x "$helper" ]]; then
        deleted_open_unknown "No se encuentra el recolector ejecutable: ${helper}"
        return 0
    fi

    if ! deleted_open_validate_config; then
        deleted_open_unknown "Configuración de DeletedOpen inválida."
        return 0
    fi

    # -------------------------------------------------------------------------
    # Temporary output directory.
    # -------------------------------------------------------------------------

    if ! output_dir="$(mktemp -d)"; then
        deleted_open_unknown "No se pudo crear el directorio temporal."
        return 0
    fi

    # -------------------------------------------------------------------------
    # Run collector.
    # -------------------------------------------------------------------------

    if DELETED_OPEN_DETAIL_LIMIT="$DELETED_OPEN_DETAIL_LIMIT" \
       DELETED_OPEN_TIMEOUT_SECONDS="$DELETED_OPEN_TIMEOUT_SECONDS" \
       "$helper" "$output_dir"; then

        helper_status=0

    else

        helper_status=$?

    fi

    if (( helper_status != 0 )); then
        rm -rf -- "$output_dir"
        deleted_open_unknown "El recolector terminó con código ${helper_status}."
        return 0
    fi

    # -------------------------------------------------------------------------
    # Validate generated files.
    # -------------------------------------------------------------------------

    for key in summary diagnostics processes details; do

        if [[ ! -f "${output_dir}/${key}.tsv" ]]; then
            rm -rf -- "$output_dir"
            deleted_open_unknown "Falta el archivo de resultados: ${key}.tsv"
            return 0
        fi

    done

    # -------------------------------------------------------------------------
    # Read summary.
    # -------------------------------------------------------------------------

    if ! IFS=$'\t' read -r \
        total_files \
        total_processes \
        total_logical \
        total_physical \
        extra < "${output_dir}/summary.tsv"; then

        rm -rf -- "$output_dir"
        deleted_open_unknown "No se pudo leer summary.tsv."
        return 0
    fi

    if [[ -n "$extra" ]] ||
       [[ ! "$total_files" =~ ^[0-9]+$ ]] ||
       [[ ! "$total_processes" =~ ^[0-9]+$ ]] ||
       [[ ! "$total_logical" =~ ^[0-9]+$ ]] ||
       [[ ! "$total_physical" =~ ^[0-9]+$ ]]; then

        rm -rf -- "$output_dir"
        deleted_open_unknown "Contenido inválido en summary.tsv."
        return 0
    fi

    # -------------------------------------------------------------------------
    # Read diagnostics.
    # -------------------------------------------------------------------------

    if ! IFS=$'\t' read -r \
        stat_errors \
        identity_errors \
        race_skips \
        warning_errors \
        ignored_warnings \
        extra < "${output_dir}/diagnostics.tsv"; then

        rm -rf -- "$output_dir"
        deleted_open_unknown "No se pudo leer diagnostics.tsv."
        return 0
    fi

    for key in \
        "$stat_errors" \
        "$identity_errors" \
        "$race_skips" \
        "$warning_errors" \
        "$ignored_warnings"; do

        if [[ ! "$key" =~ ^[0-9]+$ ]]; then
            rm -rf -- "$output_dir"
            deleted_open_unknown "Contenido inválido en diagnostics.tsv."
            return 0
        fi

    done

    if [[ -n "$extra" ]] ||
       (( stat_errors > 0 || identity_errors > 0 || warning_errors > 0 )); then

        rm -rf -- "$output_dir"
        deleted_open_unknown "La medición contiene errores de diagnóstico."
        return 0
    fi

    # -------------------------------------------------------------------------
    # Determine global status.
    # -------------------------------------------------------------------------

    if (( total_physical >= DELETED_OPEN_CRITICAL_BYTES )); then

        status="CRITICAL"
        reason="Espacio físico retenido por archivos borrados: ${total_physical} bytes."

    elif (( total_physical >= DELETED_OPEN_WARNING_BYTES )); then

        status="WARNING"
        reason="Espacio físico retenido por archivos borrados: ${total_physical} bytes."

    else

        status="OK"
        reason="Espacio físico retenido por archivos borrados dentro de los límites."

    fi

    # -------------------------------------------------------------------------
    # Update main state.
    # -------------------------------------------------------------------------

    deleted_open_state_select "deleted_open"

    sw_state_load

    sw_status_update "$status" "$reason" || {
        rm -rf -- "$output_dir"
        return 1
    }

    sw_state_set "module_version" "$MODULE_VERSION"
    sw_state_set "module.label" "Deleted Open"
    sw_state_set "module.icon" "lucide/file-x"
    sw_state_set "module.order" "$MODULE_ORDER"

    # Remove previous dynamic process entries.
    sw_state_delete_prefix "process_"

    sw_state_set "files" "$total_files"
    sw_state_set "files.label" "$(sw_translate "Unique files")"
    sw_state_set "files.order" "10"

    sw_state_set "processes" "$total_processes"
    sw_state_set "processes.label" "$(sw_translate "Processes")"
    sw_state_set "processes.order" "20"

    sw_state_set "logical" "$total_logical"
    sw_state_set "logical.label" "$(sw_translate "Logical size")"
    sw_state_set "logical.render" "bytes"
    sw_state_set "logical.order" "30"

    sw_state_set "physical" "$total_physical"
    sw_state_set "physical.label" "$(sw_translate "Physical space retained")"
    sw_state_set "physical.render" "bytes"
    sw_state_set "physical.widget" "gauge"
    sw_state_set "physical.min" "0"
    sw_state_set "physical.max" "$DELETED_OPEN_CRITICAL_BYTES"
    sw_state_set "physical.warning" "$DELETED_OPEN_WARNING_BYTES"
    sw_state_set "physical.critical" "$DELETED_OPEN_CRITICAL_BYTES"
    sw_state_set "physical.order" "40"

    # Diagnostics.
    sw_state_set "stat_errors" "$stat_errors"
    sw_state_set "stat_errors.label" "$(sw_translate "Stat errors")"
    sw_state_set "stat_errors.order" "200"

    sw_state_set "identity_errors" "$identity_errors"
    sw_state_set "identity_errors.label" "$(sw_translate "Identity errors")"
    sw_state_set "identity_errors.order" "210"

    sw_state_set "race_skips" "$race_skips"
    sw_state_set "race_skips.label" "$(sw_translate "Disappeared descriptors")"
    sw_state_set "race_skips.order" "220"

    sw_state_set "warning_errors" "$warning_errors"
    sw_state_set "warning_errors.label" "$(sw_translate "Invalidating warnings")"
    sw_state_set "warning_errors.order" "230"

    sw_state_set "ignored_warnings" "$ignored_warnings"
    sw_state_set "ignored_warnings.label" "$(sw_translate "Ignored warnings")"
    sw_state_set "ignored_warnings.order" "240"

    # -------------------------------------------------------------------------
    # Per-process breakdown.
    # -------------------------------------------------------------------------

    rank=1
    order=100

    while IFS=$'\t' read -r \
        physical logical pid uid comm process_files extra; do

        [[ -z "$physical" ]] && continue

        if [[ -n "$extra" ]] ||
           [[ ! "$physical" =~ ^[0-9]+$ ]] ||
           [[ ! "$logical" =~ ^[0-9]+$ ]] ||
           [[ ! "$pid" =~ ^[0-9]+$ ]] ||
           [[ ! "$process_files" =~ ^[0-9]+$ ]] ||
           [[ -z "$uid" || -z "$comm" ]]; then

            rm -rf -- "$output_dir"
            deleted_open_unknown "Registro inválido en processes.tsv."
            return 0
        fi

        sw_state_set "process_${rank}" "${comm} (PID ${pid})"
        sw_state_set "process_${rank}.label" "$(sw_translate "Process") ${rank}"
        sw_state_set "process_${rank}.order" "$order"

        sw_state_set "process_${rank}_files" "$process_files"
        sw_state_set "process_${rank}_files.label" "$(sw_translate "Files")"
        sw_state_set "process_${rank}_files.order" "$((order + 1))"

        sw_state_set "process_${rank}_physical" "$physical"
        sw_state_set "process_${rank}_physical.label" "$(sw_translate "Physical space")"
        sw_state_set "process_${rank}_physical.render" "bytes"
        sw_state_set "process_${rank}_physical.order" "$((order + 2))"

        sw_state_set "process_${rank}_logical" "$logical"
        sw_state_set "process_${rank}_logical.label" "$(sw_translate "Logical size")"
        sw_state_set "process_${rank}_logical.render" "bytes"
        sw_state_set "process_${rank}_logical.order" "$((order + 3))"

        sw_state_set "process_${rank}_uid" "$uid"
        sw_state_set "process_${rank}_uid.label" "UID"
        sw_state_set "process_${rank}_uid.hidden" "true"

        ((rank += 1))
        ((order += 10))

    done < "${output_dir}/processes.tsv"

    sw_state_save

    # -------------------------------------------------------------------------
    # Update independent detail state.
    # -------------------------------------------------------------------------

    if (( total_files == 0 )); then

        deleted_open_remove_detail

    else

        deleted_open_state_select "deleted_open_detail"

        sw_state_load

        sw_state_set "module_version" "$MODULE_VERSION"
        sw_state_set "module.label" "Deleted Open - Details"
        sw_state_set "module.icon" "lucide/file-x"
        sw_state_set "module.order" "$((MODULE_ORDER + 1))"

        sw_state_delete_prefix "file_"

        sw_state_set "files" "$total_files"
        sw_state_set "files.label" "$(sw_translate "Unique files")"
        sw_state_set "files.order" "10"

        rank=1
        order=20

        while IFS=$'\t' read -r \
            physical logical dev_inode pids fs_type filename extra; do

            [[ -z "$physical" ]] && continue

            if [[ -n "$extra" ]] ||
               [[ ! "$physical" =~ ^[0-9]+$ ]] ||
               [[ ! "$logical" =~ ^[0-9]+$ ]] ||
               [[ -z "$dev_inode" || -z "$pids" ||
                  -z "$fs_type" || -z "$filename" ]]; then

                rm -rf -- "$output_dir"
                deleted_open_unknown "Registro inválido en details.tsv."
                return 0
            fi

            sw_state_set "file_${rank}" "$filename"
            sw_state_set "file_${rank}.label" "#${rank}"
            sw_state_set "file_${rank}.order" "$order"

            sw_state_set "file_${rank}_physical" "$physical"
            sw_state_set "file_${rank}_physical.label" "$(sw_translate "Physical space")"
            sw_state_set "file_${rank}_physical.render" "bytes"
            sw_state_set "file_${rank}_physical.order" "$((order + 1))"

            sw_state_set "file_${rank}_logical" "$logical"
            sw_state_set "file_${rank}_logical.label" "$(sw_translate "Logical size")"
            sw_state_set "file_${rank}_logical.render" "bytes"
            sw_state_set "file_${rank}_logical.order" "$((order + 2))"

            sw_state_set "file_${rank}_filesystem" "$fs_type"
            sw_state_set "file_${rank}_filesystem.label" "Filesystem"
            sw_state_set "file_${rank}_filesystem.order" "$((order + 3))"

            sw_state_set "file_${rank}_identity" "$dev_inode"
            sw_state_set "file_${rank}_identity.label" "Device / inode"
            sw_state_set "file_${rank}_identity.order" "$((order + 4))"

            sw_state_set "file_${rank}_pids" "$pids"
            sw_state_set "file_${rank}_pids.label" "PIDs"
            sw_state_set "file_${rank}_pids.order" "$((order + 5))"

            ((rank += 1))
            ((order += 10))

        done < "${output_dir}/details.tsv"

        sw_state_save

    fi

    # -------------------------------------------------------------------------
    # Cleanup.
    # -------------------------------------------------------------------------

    rm -rf -- "$output_dir"

    return 0
}
