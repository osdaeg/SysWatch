#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# module FUTBOL
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

readonly MODULE_NAME="IESPIEN-INTERNATIONAL-FUTBOL"
readonly MODULE_DESCRIPTION="FUTBOL events"
readonly MODULE_VERSION="0.1.0"

MODULE_INTERVAL=${MODULE_INTERVAL:-21400}
MODULE_ORDER=${MODULE_ORDER:-9999}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly FUTBOL_WARNING="${FUTBOL_WARNING:-80}"
readonly FUTBOL_CRITICAL="${FUTBOL_CRITICAL:-95}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

FUTBOL_VALUE=0
FUTBOL_STATUS="${SW_STATUS_UNKNOWN}"
FUTBOL_EVENTS=()

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

FUTBOL_collect() {

    local anio mes dia
    local file cached item
    local competicion contrincantes fecha hora escenario canales

    anio=$(date +%Y)
    mes=$(date +%m)
    dia=$(date +%d)

    file="/home/daniel/docker/util/iespien/cache/fútbol_de_selecciones_${anio}-${mes}-${dia}.json"

    [[ -f "$file" ]] || return 1

    sw_cache_copy "$file"

    cached=$(sw_cache_file "fútbol_de_selecciones_${anio}-${mes}-${dia}.json")

    [[ -f "$cached" ]] || return 1

    while IFS= read -r item; do

        competicion=$(jq -r '.competicion' <<<"$item")
        contrincantes=$(jq -r '.contrincantes' <<<"$item")
        fecha=$(jq -r '.fecha' <<<"$item")
        hora=$(jq -r '.hora' <<<"$item")
        escenario=$(jq -r '.escenario' <<<"$item")
        canales=$(jq -r '.canales | join(", ")' <<<"$item")

        FUTBOL_EVENTS+=(
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

    #printf '%s\n' "${FUTBOL_EVENTS[@]}"

}

FUTBOL_analyze() {

    FUTBOL_STATUS="${SW_STATUS_OK}"

    if ((FUTBOL_VALUE >= FUTBOL_CRITICAL)); then

        FUTBOL_STATUS="${SW_STATUS_CRITICAL}"

    elif ((FUTBOL_VALUE >= FUTBOL_WARNING)); then

        FUTBOL_STATUS="${SW_STATUS_WARNING}"

    fi

}

FUTBOL_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata (consumed by lib/html.sh)
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "$(sw_translate "International football")"
    sw_state_set "module.icon" "sports/futbol"
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

    for data in "${FUTBOL_EVENTS[@]}"; do

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

FUTBOL_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "FUTBOL value: ${FUTBOL_VALUE} (${FUTBOL_STATUS})"

}

sw_module_run() {

    sw_state_use "futbol2"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    sw_state_clear

    FUTBOL_collect

    FUTBOL_analyze

    sw_status_update "${FUTBOL_STATUS}" || return 1

    FUTBOL_update_state

    sw_state_save

    FUTBOL_report

    # Optional: append to CSV history for sparkline widgets.
    #
    # sw_csv_append \
    #     "FUTBOL" \
    #     "value" \
    #     "${FUTBOL_VALUE}"

}
