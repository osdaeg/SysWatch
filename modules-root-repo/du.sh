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
readonly MODULE_DESCRIPTION="Heavy-directory finder for mounts disk.sh flagged as full"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-480}
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

    # Excludes the root's OWN line by exact path match (not by "skip
    # line 1") -- when one child dominates the parent's total (e.g. a
    # single folder eating 95%+ of the mount), du -h can round both to
    # the same displayed size, making sort's tie-break between them
    # unreliable. Matching the literal path is immune to that.

    local root="$1"

    timeout "${DU_TIMEOUT_SECONDS}" du -hx --max-depth=1 "${root}" 2>/dev/null |
        awk -v root="${root}" '$2 != root' |
        sort -rh |
        head -n 1 |
        awk '{print $2}'

}

du_top_subdirs() {

    # Prints "size\tpath" for the DU_TOP_N heaviest immediate
    # subdirectories of $1 -- same exact-path exclusion as above.

    local dir="$1"

    timeout "${DU_TIMEOUT_SECONDS}" du -hx --max-depth=1 "${dir}" 2>/dev/null |
        awk -v dir="${dir}" '$2 != dir' |
        sort -rh |
        head -n "${DU_TOP_N}"

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
        echo "pasa por aca"
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
        echo "atraviesa este lugar"
        sw_state_delete
        return

    fi

    sw_state_load

    parent=$(sw_state_get "parent")

    if [[ -z "${parent}" || ! -f "${parent}" ]]; then
        sw_state_reset
        sw_state_delete
        return
    fi

    local heaviest_dir
    heaviest_dir="$(du_find_heaviest "${mountpoint}")"

    if [[ -z "${heaviest_dir}" ]]; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "du timed out or failed for ${mountpoint}"

        return 1

    fi

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
    local size
    local path

    while read -r size path; do

        [[ -z "${path}" ]] && continue

        sw_state_set "dir${rank}" "${path} (${size})"
        sw_state_set "dir${rank}.label" "#${rank}"
        sw_state_set "dir${rank}.order" "${order}"

        (( rank++ ))
        (( order += 10 ))

    done < <(du_top_subdirs "${heaviest_dir}")

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

    for f in "${STATE_DIR}"/*.state; do

        [[ -f "${f}" ]] || continue

        grep -q "^_internal.mountpoint=" "${f}" || continue

        du_process_disk_state "${f}"

    done

}
