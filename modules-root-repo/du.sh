#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Heavy-directory finder module
#
# Deliberately dormant almost all the time: it reads disk.sh's own
# .state files (looking for the "_internal.mountpoint" marker disk.sh
# sets on each of them) and only runs `du` -- which can be slow -- for a
# mount that disk.sh has already flagged as WARNING/CRITICAL. If a mount
# is OK, this module just clears its own leftover state for that mount
# (if any) and moves on.
#
# This is the first place in SysWatch where one module reads another
# module's .state file directly instead of only writing its own -- by
# design, still fully decoupled: du.sh doesn't call disk.sh or know
# anything about how it computes its status, it only reads the marker
# and the status field, which is the same public contract any consumer
# (including the dashboard itself) already relies on.
#
# Needs root: emulates the user's own working `du`/`sudo` invocation, and
# an unprivileged `du` would undercount directories it can't read into
# (other users' homes, root-owned system paths).
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Du"
readonly MODULE_SCRIPT="$(realpath "${BASH_SOURCE[0]}")"
readonly MODULE_DESCRIPTION="Heavy-directory finder for mounts disk.sh flagged as full"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL_NORMAL:-480}
MODULE_ORDER=${MODULE_ORDER:-42}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly DU_TOP_N="${DU_TOP_N:-5}"
readonly DU_TIMEOUT_SECONDS="${DU_TIMEOUT_SECONDS:-30}"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

du_find_heaviest() {
    local root="$1"
    local tmp
    local sorted
    local rc
    local record
    local path
    local result=""

    tmp="$(mktemp)" || return 1
    sorted="$(mktemp)" || {
        rm -f -- "$tmp"
        return 1
    }

    if timeout "${DU_TIMEOUT_SECONDS}" \
        du -hx --null --max-depth=1 "$root" \
        >"$tmp" 2>/dev/null; then
        :
    else
        rc=$?
        rm -f -- "$tmp" "$sorted"
        return "$rc"
    fi

    if sort -z -rh "$tmp" >"$sorted"; then
        :
    else
        rc=$?
        rm -f -- "$tmp" "$sorted"
        return "$rc"
    fi

    while IFS= read -r -d '' record; do
        path="${record#*$'\t'}"

        [[ "$path" == "$root" ]] && continue

        result="$path"
        break
    done <"$sorted"

    rm -f -- "$tmp" "$sorted"

    [[ -n "$result" ]] || return 1

    printf '%s\n' "$result"
}

du_top_subdirs() {
    local dir="$1"
    local tmp
    local sorted
    local rc
    local record
    local size
    local path
    local count=0

    tmp="$(mktemp)" || return 1
    sorted="$(mktemp)" || {
        rm -f -- "$tmp"
        return 1
    }

    if timeout "${DU_TIMEOUT_SECONDS}" \
        du -hx --null --max-depth=1 "$dir" \
        >"$tmp" 2>/dev/null; then
        :
    else
        rc=$?
        rm -f -- "$tmp" "$sorted"
        return "$rc"
    fi

    if sort -z -rh "$tmp" >"$sorted"; then
        :
    else
        rc=$?
        rm -f -- "$tmp" "$sorted"
        return "$rc"
    fi

    while IFS= read -r -d '' record; do
        size="${record%%$'\t'*}"
        path="${record#*$'\t'}"

        [[ "$path" == "$dir" ]] && continue

        printf '%s\t%s\n' "$size" "$path"

        ((count += 1))

        ((count >= DU_TOP_N)) && break
    done <"$sorted"

    rm -f -- "$tmp" "$sorted"

    return 0
}

du_process_disk_state() {

    local disk_state_file="$1"

    local mountpoint
    local disk_status

    local parent=""

    mountpoint="$(grep "^_internal.mountpoint=" "${disk_state_file}" | cut -d'=' -f2-)"
    disk_status="$(grep "^status=" "${disk_state_file}" | cut -d'=' -f2-)"

    [[ -z "${mountpoint}" ]] && return

    local key
    key="$(basename "${disk_state_file}" .state)_du"

    sw_state_use "${key}"

    if ! mountpoint -q "${mountpoint}"; then
        sw_state_delete
        return
    fi

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    if [[ "${disk_status}" != "WARNING" && "${disk_status}" != "CRITICAL" ]]; then

        # Nothing wrong (or disk.sh hasn't run yet this cycle) --
        # clear any previous breakdown so a card doesn't linger once
        # the mount recovers.
        sw_state_delete
        return

    fi

    sw_state_load

    parent=$(sw_state_get "parent")

    if [[ -n "${parent}" && ! -f "${parent}" ]]; then
        sw_state_delete
        return
    fi

    local heaviest_dir
    local top_dirs

    # Find the heaviest directory.
    if ! heaviest_dir="$(du_find_heaviest "${mountpoint}")"; then
        sw_log_warning \
            "${MODULE_NAME}" \
            "du timed out or failed for ${mountpoint}"
        return 1
    fi

    # List its largest subdirectories.
    if ! top_dirs="$(du_top_subdirs "${heaviest_dir}")"; then
        sw_log_warning \
            "${MODULE_NAME}" \
            "du failed while listing subdirectories of ${heaviest_dir}"
        return 1
    fi

    # Both scans succeeded. Update the state.
    sw_status_update "${disk_status}" "${key}" || return

    sw_state_set "module_version" "${MODULE_VERSION}"
    sw_state_set "module.label" "du: ${mountpoint}"
    sw_state_set "module.icon" "lucide/folder-search"
    sw_state_set "module.order" "$MODULE_ORDER"

    sw_state_set "heaviest_dir" "${heaviest_dir}"
    sw_state_set "heaviest_dir.label" "$(sw_translate "Heaviest dir")"
    sw_state_set "heaviest_dir.order" "10"

    local order=20
    local rank=1
    local line
    local size
    local path

    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue

        size="${line%%$'\t'*}"
        path="${line#*$'\t'}"

        [[ -z "${path}" ]] && continue

        sw_state_set "dir${rank}" "${path} (${size})"
        sw_state_set "dir${rank}.label" "#${rank}"
        sw_state_set "dir${rank}.order" "${order}"

        ((rank++))
        ((order += 10))
    done <<<"${top_dirs}"

    # Remove obsolete directory entries.
    while ((rank <= DU_TOP_N)); do
        sw_state_delete_key "dir${rank}"
        ((rank++))
    done

    sw_state_set "parent" "$disk_state_file"
    sw_state_set "parent.hidden" "true"

    sw_state_save

    sw_log_info \
        "${MODULE_NAME}" \
        "du[${mountpoint}]: heaviest=${heaviest_dir}"

}

sw_module_run() {
    sw_require_command du || return 127

    local f
    local key
    local parent

    # Procesar los estados de disk.sh.
    for f in "${STATE_DIR}"/*.state; do
        [[ -f "${f}" ]] || continue
        grep -q "^_internal.mountpoint=" "${f}" || continue
        du_process_disk_state "${f}"
    done

    # Limpiar estados Du cuyo estado padre ya desapareció.
    for f in "${STATE_DIR}"/*_du.state; do
        [[ -f "${f}" ]] || continue

        key="$(basename "${f}" .state)"
        sw_state_use "${key}"
        sw_state_load
        parent="$(sw_state_get "parent")"

        if [[ -n "${parent}" && ! -f "${parent}" ]]; then
            sw_state_delete
            sw_log_info \
                "${MODULE_NAME}" \
                "Eliminado estado huérfano: ${key}"
        fi
    done
}
