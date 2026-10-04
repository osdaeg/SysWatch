#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Backrest (restic) backup monitoring
#
# Deliberately separate from rclone.sh: a broken rclone mount is a
# transport/filesystem problem, a failed backup is a job-outcome problem.
# The mount can be perfectly healthy and the backup can still fail (repo
# lock, permissions, retention policy, out of space) -- they have nothing
# to do with each other architecturally, even though they're often related
# in practice.
#
# Reads Backrest's HTTP API (GetOperations) for each configured plan and
# looks at the most recently COMPLETED operation that is actually a backup
# (not a hook/forget/prune/index-snapshot operation, which also show up in
# the same operation history).
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Backrest"
readonly MODULE_DESCRIPTION="Backrest (restic) backup monitoring"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-86400}
MODULE_ORDER=${MODULE_ORDER:-43}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly BACKREST_URL="${BACKREST_URL:-http://localhost:9898}"

# Comma-separated plan IDs to watch, e.g. "PlanGDriveLocal,PlanOtroPlan".
# There's no lightweight "list all plans" endpoint worth relying on, so
# this stays an explicit list -- same pattern as DISK_EXCLUDE_MOUNTS /
# DOCKER_EXCLUDE_CONTAINERS.
readonly BACKREST_PLANS="${BACKREST_PLANS:-}"

# Only needed if Backrest has basic auth enabled.
readonly BACKREST_USER="${BACKREST_USER:-}"
readonly BACKREST_PASSWORD="${BACKREST_PASSWORD:-}"

readonly BACKREST_TIMEOUT_SECONDS="${BACKREST_TIMEOUT_SECONDS:-10}"

# If the last completed backup for a plan is older than this, something
# may have stopped it from running at all (not the same as it running
# and failing, which is caught separately via its status).
readonly BACKREST_MAX_AGE_HOURS="${BACKREST_MAX_AGE_HOURS:-36}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

BACKREST_PLAN_LIST=()

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

backrest_sanitize_key() {

    local raw="$1"

    local key="${raw,,}"
    key="${key//[^a-z0-9_]/_}"

    printf '%s\n' "${key}"

}

backrest_query_plan() {

    # Prints the JSON of the latest COMPLETED backup operation for the
    # given plan, or nothing if none exist / the request failed.

    local plan="$1"

    local curl_args=(
        --silent
        --show-error
        --max-time "${BACKREST_TIMEOUT_SECONDS}"
        -X POST
        "${BACKREST_URL}/v1.Backrest/GetOperations"
        --data "{\"selector\":{\"planId\":\"${plan}\"}}"
        -H "Content-Type: application/json"
    )

    if [[ -n "${BACKREST_USER}" && -n "${BACKREST_PASSWORD}" ]]; then

        curl_args+=(-u "${BACKREST_USER}:${BACKREST_PASSWORD}")

    fi

    local response

    response="$(curl "${curl_args[@]}" 2>/dev/null)"

    [[ -z "${response}" ]] && return 1

    jq -e '
        [
            .operations[]? |
            select(.operationBackup != null) |
            select((.unixTimeEndMs // "0" | tonumber) > 0)
        ]
        | sort_by(.unixTimeEndMs | tonumber)
        | last
    ' <<<"${response}" 2>/dev/null

}

backrest_process_plan() {

    local plan="$1"
    local key="$2"

    local op
    op="$(backrest_query_plan "${plan}")" || true

    sw_state_use "${key}"
    sw_state_load
    sw_state_reset

    if [[ -z "${op}" || "${op}" == "null" ]]; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "No completed backup operations found for plan '${plan}' (wrong plan ID, or it never ran)"

        sw_status_update "${SW_STATUS_WARNING}" "${key}" || return

        sw_state_set "module_version" "${MODULE_VERSION}"
        sw_state_set "module.label" "restic: ${plan}"
        sw_state_set "module.icon" "lucide/archive"
        sw_state_set "module.order" "$MODULE_ORDER"
        sw_state_set "detail" "$(sw_translate "No runs registered")"
        sw_state_set "detail.label" "$(sw_translate "Detail")"
        sw_state_save

        return

    fi

    local status
    local end_ms
    local message
    local age_hours
    local plan_status

    status="$(jq -r '.status // "STATUS_UNKNOWN"' <<<"${op}")"
    end_ms="$(jq -r '.unixTimeEndMs // "0"' <<<"${op}")"
    message="$(jq -r '.displayMessage // ""' <<<"${op}")"

    age_hours=$((($(date +%s) - (end_ms / 1000)) / 3600))

    case "${status}" in

    STATUS_SUCCESS)

        sw_state_reset

        if ((age_hours > BACKREST_MAX_AGE_HOURS)); then

            plan_status="${SW_STATUS_WARNING}"
            message="$(printf "$(sw_translate "Last run %sh ago (expected every %sh)")\n" \
                "$age_hours" "$BACKREST_MAX_AGE_HOURS")"

        else

            plan_status="${SW_STATUS_OK}"

        fi
        ;;

    STATUS_WARNING | STATUS_SYSTEM_CANCELLED | STATUS_USER_CANCELLED)

        plan_status="${SW_STATUS_WARNING}"
        ;;

    STATUS_ERROR)

        plan_status="${SW_STATUS_CRITICAL}"
        ;;

    *)

        # STATUS_INPROGRESS / STATUS_PENDING shouldn't reach here
        # (they're filtered out by requiring unixTimeEndMs > 0), but
        # fall back safely if something unexpected shows up.
        plan_status="${SW_STATUS_WARNING}"
        ;;

    esac

    sw_status_update "${plan_status}" "${key}" || return

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.label" "restic: ${plan}"
    sw_state_set "module.icon" "lucide/archive"
    sw_state_set "module.order" "$MODULE_ORDER"

    sw_state_set "backup_status" "${status}"
    sw_state_set "backup_status.label" "$(sw_translate "Status")"

    sw_state_set "last_backup" "$(date -d "@$((end_ms / 1000))" '+%Y-%m-%d %H:%M' 2>/dev/null)"
    sw_state_set "last_backup.label" "$(sw_translate "Last run")"

    message="$(sw_sanitize_state_value "$message")"

    sw_state_set "detail" "${message}"
    sw_state_set "detail.label" "$(sw_translate "Detail")"

    if [[ "${plan_status}" == "${SW_STATUS_OK}" ]]; then

        sw_state_set "detail.hidden" "true"

    fi

    sw_state_save

    sw_log_info \
        "${MODULE_NAME}" \
        "Backrest[${plan}]: ${status}, last completed ${age_hours}h ago (${plan_status})"

}

sw_module_run() {

    sw_require_command curl || return 127
    sw_require_command jq || return 127

    if [[ -z "${BACKREST_PLANS}" ]]; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "BACKREST_PLANS is not set, nothing to watch"

        return 1

    fi

    local plans_array=()
    IFS=',' read -ra plans_array <<<"${BACKREST_PLANS}"

    local plan
    local key

    for plan in "${plans_array[@]}"; do

        [[ -z "${plan}" ]] && continue

        key="$(backrest_sanitize_key "${plan}")"

        backrest_process_plan "${plan}" "${key}"

    done

}
