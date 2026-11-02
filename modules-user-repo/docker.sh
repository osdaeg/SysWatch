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
readonly MODULE_SCRIPT="$(realpath "${BASH_SOURCE[0]}")"
readonly MODULE_DESCRIPTION="Docker container health monitoring"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-240}
MODULE_INTERVAL_NORMAL=${MODULE_INTERVAL_NORMAL:-}
MODULE_INTERVAL_ALT=${MODULE_INTERVAL_ALT:-}
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

DOCKER_DAEMON_AVAILABLE=0
DOCKER_OVERVIEW_STATUS="${SW_STATUS_OK}"

DOCKER_TOTAL=0
DOCKER_RUNNING=0
DOCKER_STOPPED=0
DOCKER_PROBLEMS=0

DOCKER_ALL_NAMES=()
DOCKER_ALL_STATES=()

DOCKER_CPU=""

DOCKER_WARNING=80
DOCKER_CRITICAL=95

DOCKER_CONTAINER_CPU=()

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
    DOCKER_STATUS=()

    # -aq (not just -q): a crashed container with no healthcheck defined
    # only shows up here if we also include stopped containers -- with
    # -q alone it would silently vanish from view instead of alerting.
    ids="$(docker ps -aq 2>/dev/null)"

    [[ -z "${ids}" ]] && return 0

    while IFS='|' read -r name policy health running_state; do

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

    local name
    local state

    DOCKER_DAEMON_AVAILABLE=0

    DOCKER_KEYS=()
    DOCKER_NAMES=()
    DOCKER_HEALTH=()
    DOCKER_RUNNING_STATE=()
    DOCKER_RESTART_POLICY=()
    DOCKER_STATUS=()

    DOCKER_ALL_NAMES=()
    DOCKER_ALL_STATES=()

    sw_require_command docker || return 0

    docker ps >/dev/null 2>&1 || {

        sw_log_warning \
            "${MODULE_NAME}" \
            "Cannot reach the Docker daemon (not running, or permission denied)"

        return 0

    }

    DOCKER_DAEMON_AVAILABLE=1

    # Inventario completo para Docker Overview.
    while IFS='|' read -r name state; do

        [[ -z "${name}" ]] && continue

        DOCKER_ALL_NAMES+=("${name}")
        DOCKER_ALL_STATES+=("${state}")

    done < <(
        docker ps -a \
            --format '{{.Names}}|{{.State}}' \
            2>/dev/null
    )

    # Inventario filtrado para las fichas individuales.
    docker_discover

}

docker_collect_cpu() {

    local stats
    local name
    local cpu
    local value
    local total
    local i

    DOCKER_CPU=""
    DOCKER_CONTAINER_CPU=()

    ((DOCKER_DAEMON_AVAILABLE)) || return 1

        # Inicializar valores individuales.
    # Los contenedores detenidos tienen consumo 0.
    # Los que están ejecutándose esperan su dato de docker stats.
    for ((i = 0; i < ${#DOCKER_KEYS[@]}; i++)); do

        if [[ "${DOCKER_RUNNING_STATE[$i]}" == "running" ]]; then
            DOCKER_CONTAINER_CPU[$i]=""
        else
            DOCKER_CONTAINER_CPU[$i]="0"
        fi

    done

    stats="$(docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}' 2>/dev/null)" ||
        return 1

    # Asociar cada medición con su contenedor.
    while IFS='|' read -r name cpu; do

        [[ -z "${name}" || -z "${cpu}" ]] && continue

        value="${cpu%\%}"

        [[ "${value}" =~ ^[0-9]+([.][0-9]+)?$ ]] || continue

        for ((i = 0; i < ${#DOCKER_NAMES[@]}; i++)); do

            if [[ "${DOCKER_NAMES[$i]}" == "${name}" ]]; then

                DOCKER_CONTAINER_CPU[$i]="${value}"
                break

            fi

        done

    done <<< "${stats}"

    # Sumar el consumo de todos los contenedores en ejecución,
    # incluidos aquellos que no tienen ficha individual.
    total="$(
        awk -F'|' '
            {
                value = $2
                sub(/%$/, "", value)

                if (value ~ /^[0-9]+([.][0-9]+)?$/) {
                    sum += value
                }
            }

            END {
                printf "%.0f\n", sum
            }
        ' <<< "${stats}"
    )" || return 1

    DOCKER_CPU="${total}"

}

docker_analyze() {

    local i
    local state

    DOCKER_TOTAL=0
    DOCKER_RUNNING=0
    DOCKER_STOPPED=0
    DOCKER_PROBLEMS=0

    if ((!DOCKER_DAEMON_AVAILABLE)); then

        DOCKER_OVERVIEW_STATUS="${SW_STATUS_CRITICAL}"

        return 0

    fi

    DOCKER_TOTAL="${#DOCKER_ALL_NAMES[@]}"

    for state in "${DOCKER_ALL_STATES[@]}"; do

        if [[ "${state}" == "running" ]]; then
            ((DOCKER_RUNNING += 1))
        else
            ((DOCKER_STOPPED += 1))
        fi

    done

    for ((i = 0; i < ${#DOCKER_KEYS[@]}; i++)); do

        DOCKER_STATUS[$i]="${SW_STATUS_OK}"

        if [[ "${DOCKER_HEALTH[$i]}" == "none" ]]; then

            if [[ "${DOCKER_RUNNING_STATE[$i]}" != "running" ]]; then

                DOCKER_STATUS[$i]="${SW_STATUS_CRITICAL}"

            fi

        elif [[ "${DOCKER_HEALTH[$i]}" == "unhealthy" ]]; then

            DOCKER_STATUS[$i]="${SW_STATUS_CRITICAL}"

        fi

        if [[ "${DOCKER_STATUS[$i]}" == "${SW_STATUS_CRITICAL}" ]]; then

            ((DOCKER_PROBLEMS += 1))

        fi

    done

    DOCKER_OVERVIEW_STATUS="${SW_STATUS_OK}"

    if ((DOCKER_PROBLEMS > 0)); then

        DOCKER_OVERVIEW_STATUS="${SW_STATUS_CRITICAL}"

    fi

}

docker_update_overview_state() {

    local key="docker_overview"
    local daemon
    local total
    local running
    local stopped
    local problems
    local cpu_max

    sw_state_use "${key}"
    sw_state_load

    cpu_max="$(sw_state_get "cpu_max")"

    [[ -z "$cpu_max" ]] && cpu_max=100

    if ((DOCKER_CPU >= cpu_max)); then

        cpu_max="$DOCKER_CPU"

    fi

    sw_state_set "cpu_max" "$cpu_max"
    sw_state_set "cpu_max.hidden" "true"

    if ((DOCKER_DAEMON_AVAILABLE)); then

        daemon="$(sw_translate "Available")"
        total="${DOCKER_TOTAL}"
        running="${DOCKER_RUNNING}"
        stopped="${DOCKER_STOPPED}"
        problems="${DOCKER_PROBLEMS}"

        sw_state_set "cpu" "${DOCKER_CPU}"
        sw_state_set "cpu.label" "CPU"
        sw_state_set "cpu.widget" "line"
        sw_state_set "cpu.unit" "%"
        sw_state_set "cpu.order" "60"
        sw_state_set "cpu.warning" "${DOCKER_WARNING}"
        sw_state_set "cpu.critical" "${DOCKER_CRITICAL}"
        sw_state_set "cpu.scale" "fixed"
        sw_state_set "cpu.min" "0"
        sw_state_set "cpu.max" "$cpu_max"

        sw_csv_append "docker_overview" "cpu" "${DOCKER_CPU}"

    else

        daemon="$(sw_translate "Unavailable")"
        total="—"
        running="—"
        stopped="—"
        problems="—"

        sw_state_delete_key "cpu"

    fi

    sw_status_update "${DOCKER_OVERVIEW_STATUS}" "${key}" || true

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.label" "Docker Overview"
    sw_state_set "module.icon" "lucide/docker"
    #sw_state_set "module.order" "$((MODULE_ORDER - 1))"
    sw_state_set "module.order" "900"

    sw_state_set "daemon" "${daemon}"
    sw_state_set "daemon.label" "$(sw_translate "Docker daemon")"
    sw_state_set "daemon.order" "10"

    sw_state_set "containers" "${total}"
    sw_state_set "containers.label" "$(sw_translate "Watched containers")"
    sw_state_set "containers.order" "20"

    sw_state_set "running" "${running}"
    sw_state_set "running.label" "$(sw_translate "Running")"
    sw_state_set "running.order" "30"

    sw_state_set "stopped" "${stopped}"
    sw_state_set "stopped.label" "$(sw_translate "Stopped")"
    sw_state_set "stopped.order" "40"

    sw_state_set "problems" "${problems}"
    sw_state_set "problems.label" "$(sw_translate "Problems")"
    sw_state_set "problems.order" "50"

    sw_timer_create "${key}" "10" "deletestate"

    sw_state_save

}

docker_update_state() {

    local i
    local key
    local cpu_csv
    local cpu_max

    docker_update_overview_state

    ((DOCKER_DAEMON_AVAILABLE)) || return 0

    for ((i = 0; i < ${#DOCKER_KEYS[@]}; i++)); do

        key="${DOCKER_KEYS[$i]}"

        sw_state_use "${key}"
        sw_state_load

        sw_status_update "${DOCKER_STATUS[$i]}" "${key}" || continue

        sw_state_set "module_version" "${MODULE_VERSION}"

        sw_state_set "module.label" "${DOCKER_NAMES[$i]}"
        sw_state_set "module.icon" "lucide/docker"
        sw_state_set "module.order" "$MODULE_ORDER"

        sw_state_delete_key "cpu"

        if [[ -n "${DOCKER_CONTAINER_CPU[$i]}" ]]; then

            sw_state_set "cpu" "${DOCKER_CONTAINER_CPU[$i]}"
            sw_state_set "cpu.label" "CPU"
            sw_state_set "cpu.unit" "%"
            sw_state_set "cpu.order" "60"

            cpu_csv="$(awk \
                -v value="${DOCKER_CONTAINER_CPU[$i]}" \
                'BEGIN { printf "%.0f", value }')"

            sw_csv_append "${key}" "cpu" "${DOCKER_CPU}"

            cpu_max="$(sw_state_get "cpu_max")"

            cpu_max=${cpu_max:-$cpu_csv}

            if ((cpu_csv >= cpu_max)); then
                cpu_max="$cpu_csv"

                sw_state_set "cpu_max" "$cpu_max"
                sw_state_set "cpu_max.hidden" "true"
            fi

            if ((cpu_csv >= 50)); then
                sw_state_set "cpu.widget" "line"
                sw_state_set "cpu.order" "60"
                sw_state_set "cpu.warning" "${DOCKER_WARNING}"
                sw_state_set "cpu.critical" "${DOCKER_CRITICAL}"
                sw_state_set "cpu.scale" "fixed"
                sw_state_set "cpu.min" "0"
                sw_state_set "cpu.max" "$cpu_max"
            fi

        fi

        if [[ "${DOCKER_HEALTH[$i]}" == "none" ]]; then

            sw_state_set "state" "${DOCKER_RUNNING_STATE[$i]}"
            sw_state_set "state.label" "$(sw_translate "Status")"

            sw_state_set "health" ""
            sw_state_set "health.hidden" "true"

        else

            sw_state_set "health" "${DOCKER_HEALTH[$i]}"
            sw_state_set "health.label" "$(sw_translate "Healthcheck")"

            sw_state_set "state" ""
            sw_state_set "state.hidden" "true"

        fi

        sw_state_set "restart_policy" "${DOCKER_RESTART_POLICY[$i]}"
        sw_state_set "restart_policy.label" "$(sw_translate "Restart policy")"

        sw_timer_create "${key}" "5" "deletestate"

        sw_state_save

    done

}

docker_report() {

    local i
    local summary=""
    local signal

    if ((!DOCKER_DAEMON_AVAILABLE)); then
        return 0
    fi

    for ((i = 0; i < ${#DOCKER_KEYS[@]}; i++)); do

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

    ((uptime_seconds < DOCKER_STARTUP_GRACE_SECONDS))

}

sw_module_run() {

    if docker_within_startup_grace; then

        sw_log_info \
            "${MODULE_NAME}" \
            "System just booted, skipping this cycle (grace period ${DOCKER_STARTUP_GRACE_SECONDS}s)"

        return 1

    fi

    docker_collect || return 1

    docker_collect_cpu

    docker_analyze

    docker_update_state

    docker_report

}
