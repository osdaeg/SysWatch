#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# task.sh
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Tasks"
readonly MODULE_DESCRIPTION="Task management"
readonly MODULE_VERSION="0.1.1"

MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-75}
MODULE_REMOTE=${MODULE_REMOTE:-""}

source "${HELPERS_DIR}/task_common.sh"
source "${HELPERS_DIR}/task_google.sh"
source "${HELPERS_DIR}/task_caldav.sh"

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

TASK_STATUS="${SW_STATUS_UNKNOWN}"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

task_sanitize_date() {
    local date="$1"

    if [[ "${date}" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2}) ]]; then
        printf '%s-%s-%s\n' \
            "${BASH_REMATCH[1]}" \
            "${BASH_REMATCH[2]}" \
            "${BASH_REMATCH[3]}"
        return 0
    fi

    if [[ "${date}" =~ ^([0-9]{4})([0-9]{2})([0-9]{2}) ]]; then
        printf '%s-%s-%s\n' \
            "${BASH_REMATCH[1]}" \
            "${BASH_REMATCH[2]}" \
            "${BASH_REMATCH[3]}"
        return 0
    fi

    return 1
}

task_collect() {

    sw_task_reset

    gtask_collect || return 1
    caldavtask_collect || return 1

}

task_analyze() {
    local list_index="$1"
    local task_index
    local task_status
    local task_due
    local due_date
    local today
    local due_epoch
    local today_epoch
    local days
    local status="${SW_STATUS_OK}"

    today="$(date +%Y-%m-%d)"
    today_epoch="$(date -d "${today}" +%s)"

    for task_index in ${SW_TASK_LIST_TASKS[list_index]}; do
        task_status="${SW_TASK_STATUSES[task_index]}"
        task_due="${SW_TASK_DUES[task_index]}"

        # Las tareas completadas no afectan el estado.
        case "${task_status}" in
        completed | COMPLETED)
            continue
            ;;
        esac

        # Sin vencimiento: no afecta el estado.
        task_due="${SW_TASK_DUES[task_index]}"

        # Sin vencimiento: la tarea sigue siendo válida,
        # pero no afecta el status de la lista.
        if [[ -z "${task_due}" ]]; then
            continue
        fi

        task_due="$(task_sanitize_date "${task_due}")" || continue

        # Nos interesa solamente la fecha.
        due_date="${task_due:0:10}"

        # Ignorar fechas que no podamos interpretar.
        due_epoch="$(date -d "${due_date}" +%s 2>/dev/null)" || continue

        days=$(((due_epoch - today_epoch) / 86400))

        case "${days}" in
        0 | -*)
            status="${SW_STATUS_CRITICAL}"
            ;;
        1)
            [[ "${status}" != "${SW_STATUS_CRITICAL}" ]] &&
                status="${SW_STATUS_CRITICAL}"
            ;;
        2)
            if [[ "${status}" != "${SW_STATUS_CRITICAL}" ]]; then
                status="${SW_STATUS_WARNING}"
            fi
            ;;
        3)
            if [[ "${status}" == "${SW_STATUS_OK}" ]]; then
                status="${SW_STATUS_INFO}"
            fi
            ;;
        esac

        # Ya no podemos obtener un estado superior.
        [[ "${status}" == "${SW_STATUS_CRITICAL}" ]] && break
    done

    SW_TASK_LIST_STATUS[list_index]="${status}"
}

task_update_state() {
    local list_count
    local list_index
    local task_index
    local task_id
    local task_title
    local task_due
    local task_status
    local task_percent
    local list_source
    local list_id
    local list_name
    local state_name
    local old_count

    list_count="$(sw_task_list_count)"

    for ((list_index = 0; list_index < list_count; list_index++)); do

        list_source="${SW_TASK_LIST_SOURCES[list_index]}"
        list_id="${SW_TASK_LIST_IDS[list_index]}"
        list_name="${SW_TASK_LIST_NAMES[list_index]}"

        # Nombre estable para el state de esta lista.
        state_name="task-${list_source}-${list_id}"

        # Eliminar caracteres problemáticos del nombre.
        state_name="$(
            sed 's#[^[:alnum:]_.-]#_#g' <<<"${state_name}"
        )"

        task_analyze "${list_index}"

        sw_state_use "${state_name}"

        if [[ -n "$MODULE_REMOTE" ]]; then
            sw_state_remote "$MODULE_REMOTE"
        fi

        sw_state_load

        if [[ -n "${list_name}" ]]; then
            sw_state_set "module.label" "${list_name}"
        else
            sw_state_set "module.label" "$(sw_translate "Tasks")"
        fi

        sw_state_set "module.icon" "lucide/list-checks"
        sw_state_set "module.order" "$MODULE_ORDER"
        sw_state_set "module_version" "${MODULE_VERSION}"

        # Eliminar las tareas que pudieran haber quedado
        # de una ejecución anterior.
        old_count="$(sw_state_get "count")"
        old_count="${old_count:-0}"

        for ((task_index = 1; task_index <= old_count; task_index++)); do
            sw_state_delete_key "task${task_index}"
            sw_state_delete_key "task${task_index}.label"
        done

        # Cargar las tareas actuales.
        old_count=0

        for task_index in ${SW_TASK_LIST_TASKS[list_index]}; do
            task_id="${SW_TASK_IDS[task_index]}"
            task_title="${SW_TASK_TITLES[task_index]}"
            task_due="${SW_TASK_DUES[task_index]}"
            task_status="${SW_TASK_STATUSES[task_index]}"
            task_percent="${SW_TASK_PERCENTS[task_index]}"

            if [[ -n "${task_due}" ]]; then
                task_due="$(task_sanitize_date "${task_due}")"
            fi

            case "${task_status}" in
            needsAction | NEEDS-ACTION)
                task_status="pendiente"
                ;;
            completed | COMPLETED)
                task_status="completada"
                ;;
            esac

            ((old_count++))

            sw_state_set \
                "task${old_count}" \
                "${task_status} ${task_due}"

            sw_state_set \
                "task${old_count}.label" \
                "${task_title}"
        done

        sw_state_set "count" "${old_count}"
        sw_state_set "count.hidden" "true"

        sw_status_update \
            "${SW_TASK_LIST_STATUS[list_index]}" \
            "${list_name:-Tasks}"

        sw_state_save
    done
}

task_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Task lists: $(sw_task_list_count) (${TASK_STATUS})"

}

sw_module_run() {

    task_collect

    sw_status_update "${TASK_STATUS}" || return 1

    task_update_state

    task_report

}
