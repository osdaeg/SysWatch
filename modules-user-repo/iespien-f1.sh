#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# module F1
#
# Requires IESPIEN (https://github.com/osdaeg/iespien)
#
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="IESPIEN-F1"
readonly MODULE_DESCRIPTION="F1 events"
readonly MODULE_VERSION="0.1.0"

MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-10}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly F1_WARNING="${F1_WARNING:-80}"
readonly F1_CRITICAL="${F1_CRITICAL:-95}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

F1_VALUE=0
F1_STATUS="${SW_STATUS_UNKNOWN}"
F1_EVENTS=()

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

F1_collect() {

    local anio mes dia
    local file cached item
    local competicion contrincantes fecha hora escenario canales

    anio=$(date +%Y)
    mes=$(date +%m)
    dia=$(date +%d)

    file="/home/daniel/docker/util/iespien/cache/fórmula_1_${anio}-${mes}-${dia}.json"

    [[ -f "$file" ]] || return 1

    sw_cache_copy "$file"

    cached=$(sw_cache_file "fórmula_1_${anio}-${mes}-${dia}.json")

    [[ -f "$cached" ]] || return 1

    while IFS= read -r item; do

        competicion=$(jq -r '.competicion' <<<"$item")
        contrincantes=$(jq -r '.contrincantes' <<<"$item")
        fecha=$(jq -r '.fecha' <<<"$item")
        hora=$(jq -r '.hora' <<<"$item")
        escenario=$(jq -r '.escenario' <<<"$item")
        canales=$(jq -r '.canales | join(", ")' <<<"$item")

        F1_EVENTS+=(
            "${competicion}|${contrincantes}|${fecha}|${hora}|${escenario}|${canales}"
        )

    done < <(
        jq -c '
        .eventos
        | sort_by(
            .competicion,
            (.fecha | split("/") | reverse | join("")),
            .hora
        )[]
    ' "$cached"
    )

    #printf '%s\n' "${F1_EVENTS[@]}"

}

F1_analyze() {

    F1_STATUS="${SW_STATUS_OK}"

    if ((F1_VALUE >= F1_CRITICAL)); then

        F1_STATUS="${SW_STATUS_CRITICAL}"

    elif ((F1_VALUE >= F1_WARNING)); then

        F1_STATUS="${SW_STATUS_WARNING}"

    fi

}

F1_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata (consumed by lib/html.sh)
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "$(sw_translate "F1")"
    sw_state_set "module.icon" "sports/f1"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Data
    # -------------------------------------------------------------------------

    local data

    local competicion contrincantes fecha hora escenario canales
    local row=1
    local competition=1
    local order=10
    local previous="previo"
    local event

    for data in "${F1_EVENTS[@]}"; do

        IFS='|' read -r competicion contrincantes fecha hora escenario canales <<<"$data"

        event=""

        [[ -n "$contrincantes" ]] && event="${contrincantes}"
        [[ -n "$fecha" ]] && event+=" - ${fecha}"
        [[ -n "$hora" ]] && event+=" - ${hora}"
        [[ -n "$escenario" ]] && event+=" - ${escenario}"
        [[ -n "$canales" ]] && event+=" - ${canales}"

        if [ "$competicion" == "$previous" ]; then
            sw_state_set "evento${row}-${competition}" "$event"
            sw_state_set "evento${row}-${competition}.label" "$row"
            sw_state_set "evento${row}-${competition}.order" "$order"
        else
            sw_state_set "competicion${competition}" "$competicion"
            sw_state_set "competicion${competition}.label" "$(sw_translate "Competition")"
            sw_state_set "competicion${competition}.order" "$order"
            sw_state_set "competicion${competition}.color" "green"

            row=1
            previous="$competicion"
            ((order++))
            sw_state_set "evento${row}-${competition}" "$event"
            sw_state_set "evento${row}-${competition}.label" "$row"
            sw_state_set "evento${row}-${competition}.order" "$order"
            ((competition++))
        fi

        ((order++))
        ((row++))

    done

}

F1_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "F1 value: ${F1_VALUE} (${F1_STATUS})"

}

sw_module_run() {

    sw_state_use "F1"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    sw_state_clear

    F1_collect

    F1_analyze

    sw_status_update "${F1_STATUS}" || return 1

    F1_update_state

    sw_state_save

    F1_report

    # Optional: append to CSV history for sparkline widgets.
    #
    # sw_csv_append \
    #     "F1" \
    #     "value" \
    #     "${F1_VALUE}"

}
