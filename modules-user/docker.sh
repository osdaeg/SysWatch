#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Docker container health monitoring
#
# Scope, on purpose: only containers with restart policy always/
# unless-stopped are considered (containers you stop yourself shouldn't
# alert). Containers WITH a healthcheck are flagged on an explicit
# "unhealthy" status. Containers WITHOUT one (most custom/homelab
# containers won't define one) are instead flagged if they're not
# actually running -- that's the only signal available for them, but it's
# better than no visibility at all.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Docker"
readonly MODULE_DESCRIPTION="Docker container health monitoring"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-240}
MODULE_ORDER=${MODULE_ORDER:-60}
MODULE_REMOTE=${MODULE_REMOTE:-""}


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# Comma-separated restart policies that make a container "worth watching".
# Containers with any other policy (no, on-failure, etc.) are skipped.
readonly DOCKER_RESTART_POLICIES="${DOCKER_RESTART_POLICIES:-always,unless-stopped}"

# Comma-separated container names to always skip, regardless of restart
# policy. Useful for on-demand containers (e.g. DB containers started by
# a dependent stack via `docker start` and stopped again at boot) where
# "running"/"exited"/health don't mean anything by themselves -- being
# stopped is entirely intentional most of the time.
readonly DOCKER_EXCLUDE_CONTAINERS="${DOCKER_EXCLUDE_CONTAINERS:-}"

# Right after boot, containers can take a while to go from
# created/restarting to actually running (slow-starting services,
# dependency chains) -- skip evaluating anything during this window
# rather than falsely reporting CRITICAL for containers that just
# haven't finished starting yet.
readonly DOCKER_STARTUP_GRACE_SECONDS="${DOCKER_STARTUP_GRACE_SECONDS:-120}"

# Overridable for testing; normally always /proc/uptime.
readonly DOCKER_UPTIME_SOURCE="${DOCKER_UPTIME_SOURCE:-/proc/uptime}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

DOCKER_KEYS=()
DOCKER_NAMES=()
DOCKER_HEALTH=()
DOCKER_RUNNING_STATE=()
DOCKER_RESTART_POLICY=()
DOCKER_STATUS=()

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

docker_sanitize_key() {

    local raw="$1"

    local key="${raw#/}"
    key="${key,,}"
    key="${key//[^a-z0-9_]/_}"

    printf '%s\n' "${key}"

}

docker_policy_is_watched() {

    local policy="$1"

    local IFS=','
    local watched

    for watched in ${DOCKER_RESTART_POLICIES}; do

        [[ "${policy}" == "${watched}" ]] && return 0

    done

    return 1

}

docker_is_excluded() {

    local name="$1"

    [[ -z "${DOCKER_EXCLUDE_CONTAINERS}" ]] && return 1

    local IFS=','
    local excluded

    for excluded in ${DOCKER_EXCLUDE_CONTAINERS}; do

        [[ "${name}" == "${excluded}" ]] && return 0

    done

    return 1

}

docker_discover() {

    local ids
    local name
    local policy
    local health
    local running_state

    DOCKER_KEYS=()
    DOCKER_NAMES=()
    DOCKER_HEALTH=()
    DOCKER_RUNNING_STATE=()
    DOCKER_RESTART_POLICY=()

    # -aq (not just -q): a crashed container with no healthcheck defined
    # only shows up here if we also include stopped containers -- with
    # -q alone it would silently vanish from view instead of alerting.
    ids="$(docker ps -aq 2>/dev/null)"

    [[ -z "${ids}" ]] && return 0

    while IFS='|' read -r name policy health running_state
    do

        if [[ -z "${name}" ]]; then continue; fi

        if ! docker_policy_is_watched "${policy}"; then continue; fi

        if docker_is_excluded "${name#/}"; then continue; fi

        DOCKER_KEYS+=("$(docker_sanitize_key "${name}")")
        DOCKER_NAMES+=("${name#/}")
        DOCKER_RESTART_POLICY+=("${policy}")
        DOCKER_HEALTH+=("${health}")
        DOCKER_RUNNING_STATE+=("${running_state}")

    done < <(
        # shellcheck disable=SC2086
        docker inspect \
            --format '{{.Name}}|{{.HostConfig.RestartPolicy.Name}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}|{{.State.Status}}' \
            ${ids} \
            2>/dev/null
    )

}

docker_collect() {

    sw_require_command docker || return 127

    docker ps >/dev/null 2>&1 || {

        sw_log_warning \
            "${MODULE_NAME}" \
            "Cannot reach the Docker daemon (not running, or permission denied)"

        return 1

    }

    docker_discover

}

docker_analyze() {

    local i

    for (( i=0; i<${#DOCKER_KEYS[@]}; i++ ))
    do

        DOCKER_STATUS[$i]="${SW_STATUS_OK}"

        if [[ "${DOCKER_HEALTH[$i]}" == "none" ]]; then

            # No healthcheck defined -- the only signal we have is
            # whether the container is actually running. A container
            # with restart policy always/unless-stopped that isn't
            # "running" almost certainly crashed (Docker would have
            # already restarted it otherwise).
            if [[ "${DOCKER_RUNNING_STATE[$i]}" != "running" ]]; then

                DOCKER_STATUS[$i]="${SW_STATUS_CRITICAL}"

            fi

        else

            if [[ "${DOCKER_HEALTH[$i]}" == "unhealthy" ]]; then

                DOCKER_STATUS[$i]="${SW_STATUS_CRITICAL}"

            fi

        fi

    done

}

docker_update_state() {

    local i
    local key

    for (( i=0; i<${#DOCKER_KEYS[@]}; i++ )); do

        key="${DOCKER_KEYS[$i]}"

        sw_state_use "${key}"
        sw_state_load

        sw_status_update "${DOCKER_STATUS[$i]}" "${key}" || continue

        sw_state_set "module_version" "${MODULE_VERSION}"

        sw_state_set "module.label" "${DOCKER_NAMES[$i]}"
        sw_state_set "module.icon" "lucide/docker"
        sw_state_set "module.order" "$MODULE_ORDER"

        if [[ "${DOCKER_HEALTH[$i]}" == "none" ]]; then

            sw_state_set "state" "${DOCKER_RUNNING_STATE[$i]}"
            sw_state_set "state.label" "Estado"

            sw_state_set "health" ""
            sw_state_set "health.hidden" "true"

        else

            sw_state_set "health" "${DOCKER_HEALTH[$i]}"
            sw_state_set "health.label" "Healthcheck"

            sw_state_set "state" ""
            sw_state_set "state.hidden" "true"

        fi

        sw_state_set "restart_policy" "${DOCKER_RESTART_POLICY[$i]}"
        sw_state_set "restart_policy.label" "Restart policy"

        sw_timer_create "${key}" "5" "deletestate"

        sw_state_save

    done

}

docker_report() {

    local i
    local summary=""
    local signal

    for (( i=0; i<${#DOCKER_KEYS[@]}; i++ )); do

        signal="${DOCKER_HEALTH[$i]}"
        [[ "${signal}" == "none" ]] && signal="${DOCKER_RUNNING_STATE[$i]}"

        summary+="${DOCKER_NAMES[$i]}=${signal} "

    done

    sw_log_info \
        "${MODULE_NAME}" \
        "Docker: ${#DOCKER_KEYS[@]} watched container(s): ${summary}"

}

docker_within_startup_grace() {

    [[ -r "${DOCKER_UPTIME_SOURCE}" ]] || return 1

    local uptime_seconds
    uptime_seconds="$(cut -d'.' -f1 "${DOCKER_UPTIME_SOURCE}" 2>/dev/null)"

    [[ "${uptime_seconds}" =~ ^[0-9]+$ ]] || return 1

    (( uptime_seconds < DOCKER_STARTUP_GRACE_SECONDS ))

}

sw_module_run() {

    if docker_within_startup_grace; then

        sw_log_info \
            "${MODULE_NAME}" \
            "System just booted, skipping this cycle (grace period ${DOCKER_STARTUP_GRACE_SECONDS}s)"

        return 1

    fi

    docker_collect || return 1

    docker_analyze

    docker_update_state

    docker_report

}
