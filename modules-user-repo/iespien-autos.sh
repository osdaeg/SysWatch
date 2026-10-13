#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# module AUTOMOVILISMO
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

readonly MODULE_NAME="IESPIEN-AUTOMOVILISMO"
readonly MODULE_DESCRIPTION="AUTOMOVILISMO events"
readonly MODULE_VERSION="0.1.0"

MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-10}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly AUTOMOVILISMO_WARNING="${AUTOMOVILISMO_WARNING:-80}"
readonly AUTOMOVILISMO_CRITICAL="${AUTOMOVILISMO_CRITICAL:-95}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

AUTOMOVILISMO_VALUE=0
AUTOMOVILISMO_STATUS="${SW_STATUS_UNKNOWN}"
AUTOMOVILISMO_EVENTS=()

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

AUTOMOVILISMO_collect() {

    local anio mes dia
    local file cached item
    local competicion contrincantes fecha hora escenario canales

    anio=$(date +%Y)
    mes=$(date +%m)
    dia=$(date +%d)

    file="/home/daniel/docker/util/iespien/cache/automovilismo_en_argentina_${anio}-${mes}-${dia}.json"

    [[ -f "$file" ]] || return 1

    sw_cache_copy "$file"

    cached=$(sw_cache_file "automovilismo_en_argentina_${anio}-${mes}-${dia}.json")

    [[ -f "$cached" ]] || return 1

    while IFS= read -r item; do

        competicion=$(jq -r '.competicion' <<<"$item")
        contrincantes=$(jq -r '.contrincantes' <<<"$item")
        fecha=$(jq -r '.fecha' <<<"$item")
        hora=$(jq -r '.hora' <<<"$item")
        escenario=$(jq -r '.escenario' <<<"$item")
        canales=$(jq -r '.canales | join(", ")' <<<"$item")

        AUTOMOVILISMO_EVENTS+=(
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

    #printf '%s\n' "${AUTOMOVILISMO_EVENTS[@]}"

}

AUTOMOVILISMO_analyze() {

    AUTOMOVILISMO_STATUS="${SW_STATUS_OK}"

    if ((AUTOMOVILISMO_VALUE >= AUTOMOVILISMO_CRITICAL)); then

        AUTOMOVILISMO_STATUS="${SW_STATUS_CRITICAL}"

    elif ((AUTOMOVILISMO_VALUE >= AUTOMOVILISMO_WARNING)); then

        AUTOMOVILISMO_STATUS="${SW_STATUS_WARNING}"

    fi

}

AUTOMOVILISMO_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata (consumed by lib/html.sh)
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "$(sw_translate "Motoring")"
    sw_state_set "module.icon" "sports/auto"
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
    local evento
    for data in "${AUTOMOVILISMO_EVENTS[@]}"; do

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
            ((row++))
        else
            sw_state_set "competicion${competition}" "$competicion"
            sw_state_set "competicion${competition}.label" "$(sw_translate "Competition")"
            sw_state_set "competicion${competition}.order" "$order"
            sw_state_set "competicion${competition}.color" "green"
            ((competition++))
            row=1
            previous="$competicion"
            ((order++))
            sw_state_set "evento${row}-${competition}" "$event"
            sw_state_set "evento${row}-${competition}.label" "$row"
            sw_state_set "evento${row}-${competition}.order" "$order"
            ((row++))
        fi

        ((order++))

    done

}

AUTOMOVILISMO_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "AUTOMOVILISMO value: ${AUTOMOVILISMO_VALUE} (${AUTOMOVILISMO_STATUS})"

}

sw_module_run() {

    sw_state_use "automovilismo"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    sw_state_clear

    AUTOMOVILISMO_collect

    AUTOMOVILISMO_analyze

    sw_status_update "${AUTOMOVILISMO_STATUS}" || return 1

    AUTOMOVILISMO_update_state

    sw_state_save

    AUTOMOVILISMO_report

    # Optional: append to CSV history for sparkline widgets.
    #
    # sw_csv_append \
    #     "AUTOMOVILISMO" \
    #     "value" \
    #     "${AUTOMOVILISMO_VALUE}"

}
