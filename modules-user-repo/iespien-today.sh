#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# module template
#
# Copy this file into modules-user/ or modules-root/, rename it, and replace
# every "IESPIEN"/"IESPIEN" placeholder with your module's name.
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="IESPIEN"
readonly MODULE_DESCRIPTION="IESPIEN events now"
readonly MODULE_VERSION="0.1.0"

MODULE_INTERVAL=${MODULE_INTERVAL:-840}
MODULE_ORDER=${MODULE_ORDER:-10}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly IESPIEN_WARNING="${IESPIEN_WARNING:-80}"
readonly IESPIEN_CRITICAL="${IESPIEN_CRITICAL:-95}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

IESPIEN_VALUE=0
IESPIEN_STATUS="${SW_STATUS_UNKNOWN}"
IESPIEN_TODAY=()

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

IESPIEN_collect() {

    # Collect raw metrics here.
    # This step should not determine the module status.

    IESPIEN_VALUE=0

}

IESPIEN_analyze() {

    IESPIEN_STATUS="${SW_STATUS_OK}"

    if ((IESPIEN_VALUE >= IESPIEN_CRITICAL)); then

        IESPIEN_STATUS="${SW_STATUS_CRITICAL}"

    elif ((IESPIEN_VALUE >= IESPIEN_WARNING)); then

        IESPIEN_STATUS="${SW_STATUS_WARNING}"

    fi

}

IESPIEN_update_state() {

    local competicion evento lista
    local elemento
    local ts_evaluar ts_actual limite_inferior limite_superior limite_inferior_legible limite_superior_legible

    local dia mes anio

    local competition=1
    local event=1

    ts_actual=$(date +%s)

    limite_inferior=$((ts_actual - 7200))
    limite_superior=$((ts_actual + 900))

    limite_inferior_legible=$(date -d "@$limite_inferior" +"%H:%M")
    limite_superior_legible=$(date -d "@$limite_superior" +"%H:%M")

    IFS=, read -r -a state <<<"$IESPIEN_STATES"

    IESPIEN_STATUS="$SW_STATUS_OK"

    for elemento in "${state[@]}"; do

        sw_state_use "$elemento"

        sw_state_load

        competition=1

        while true; do

            competicion=$(sw_state_get "competicion${competition}")

            [[ -z "$competicion" ]] && break

            event=1

            while true; do

                evento=$(sw_state_get "evento${event}-${competition}")

                [[ -z "$evento" ]] && break

                evento="${evento// - /|}"

                IFS='|' read -r -a lista <<<"$evento"

                [[ -z "${lista[2]-}" ]] && {
                    ((event++))
                    continue
                }

                IFS=/ read -r dia mes anio <<<"${lista[1]}"

                ts_evaluar=$(date -d "${anio}-${mes}-${dia} ${lista[2]}" +%s 2>/dev/null) || {
                    echo "Fecha inválida: ${lista[1]} ${lista[2]}"
                    ((event++))
                    continue
                }

                if [[ "$ts_evaluar" -ge "$limite_inferior" &&
                    "$ts_evaluar" -le "$limite_superior" ]]; then

                    IESPIEN_TODAY+=("${competicion}|${lista[0]}")
                    IESPIEN_STATUS="$SW_STATUS_INFO"
                    sw_timer_create "iespien" "5" "statusok"

                fi

                ((event++))

            done

            ((competition++))

        done

        sw_state_clear

    done

    sw_state_use "iespien"

    sw_state_load

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_clear

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata (consumed by lib/html.sh)
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "$(sw_translate "Sports events now")"
    sw_state_set "module.icon" "sports/futbol"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Data
    # -------------------------------------------------------------------------

    competition=0
    event=1

    local previous="previo"
    local order=10

    sw_state_set "hora_inferior" "$limite_inferior_legible"
    sw_state_set "hora_inferior.label" "$(sw_translate "From:")"
    sw_state_set "hora_inferior.order" "$order"
    ((order++))

    sw_state_set "hora_superior" "$limite_superior_legible"
    sw_state_set "hora_superior.label" "$(sw_translate "To:")"
    sw_state_set "hora_superior.order" "$order"
    ((order++))

    for renglon in "${IESPIEN_TODAY[@]}"; do

        IFS='|' read -r competicion evento <<<"$renglon"

        if [ "$competicion" == "$previous" ]; then
            sw_state_set "evento${event}-${competition}" "$evento"
            sw_state_set "evento${event}-${competition}.label" "$event"
            sw_state_set "evento${event}-${competition}.order" "$order"
        else
            ((competition++))
            sw_state_set "competicion${competition}" "$competicion"
            sw_state_set "competicion${competition}.label" "$(sw_translate "Competition")"
            sw_state_set "competicion${competition}.order" "$order"
            sw_state_set "competicion${competition}.color" "green"

            event=1
            previous="$competicion"
            ((order++))
            sw_state_set "evento${event}-${competition}" "$evento"
            sw_state_set "evento${event}-${competition}.label" "$event"
            sw_state_set "evento${event}-${competition}.order" "$order"
        fi

        ((order++))
        ((event++))

    done

    sw_status_update "${IESPIEN_STATUS}" || return 1

    sw_state_save

}

IESPIEN_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "IESPIEN value: ${IESPIEN_VALUE} (${IESPIEN_STATUS})"

}

sw_module_run() {

    sw_module_load_config "iespien"

    IESPIEN_update_state

    IESPIEN_report

    # Optional: append to CSV history for sparkline widgets.
    #
    # sw_csv_append \
    #     "IESPIEN" \
    #     "value" \
    #     "${IESPIEN_VALUE}"

}
