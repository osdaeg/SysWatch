#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# module BASQUET
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

readonly MODULE_NAME="IESPIEN-BASQUET"
readonly MODULE_SCRIPT="$(realpath "${BASH_SOURCE[0]}")"
readonly MODULE_DESCRIPTION="BASQUET events"
readonly MODULE_VERSION="0.1.0"

MODULE_INTERVAL=${MODULE_INTERVAL:-21400}
MODULE_INTERVAL_NORMAL=${MODULE_INTERVAL_NORMAL:-}
MODULE_INTERVAL_ALT=${MODULE_INTERVAL_ALT:-}
MODULE_ORDER=${MODULE_ORDER:-9999}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly BASQUET_WARNING="${BASQUET_WARNING:-80}"
readonly BASQUET_CRITICAL="${BASQUET_CRITICAL:-95}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

BASQUET_VALUE=0
BASQUET_STATUS="${SW_STATUS_UNKNOWN}"
BASQUET_EVENTS=()

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

BASQUET_collect() {

    local anio mes dia
    local file cached item
    local competicion contrincantes fecha hora escenario canales

    anio=$(date +%Y)
    mes=$(date +%m)
    dia=$(date +%d)

    file="/home/daniel/docker/util/iespien/cache/básquet_${anio}-${mes}-${dia}.json"

    [[ -f "$file" ]] || return 1

    sw_cache_copy "$file"

    cached=$(sw_cache_file "básquet_${anio}-${mes}-${dia}.json")

    [[ -f "$cached" ]] || return 1

    while IFS= read -r item; do

        competicion=$(jq -r '.competicion' <<<"$item")
        contrincantes=$(jq -r '.contrincantes' <<<"$item")
        fecha=$(jq -r '.fecha' <<<"$item")
        hora=$(jq -r '.hora' <<<"$item")
        escenario=$(jq -r '.escenario' <<<"$item")
        canales=$(jq -r '.canales | join(", ")' <<<"$item")

        BASQUET_EVENTS+=(
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

    #printf '%s\n' "${BASQUET_EVENTS[@]}"

}

BASQUET_analyze() {

    BASQUET_STATUS="${SW_STATUS_OK}"

    if ((BASQUET_VALUE >= BASQUET_CRITICAL)); then

        BASQUET_STATUS="${SW_STATUS_CRITICAL}"

    elif ((BASQUET_VALUE >= BASQUET_WARNING)); then

        BASQUET_STATUS="${SW_STATUS_WARNING}"

    fi

}

BASQUET_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata (consumed by lib/html.sh)
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "$(sw_translate "Basket")"
    sw_state_set "module.icon" "sports/basquet"
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

    for data in "${BASQUET_EVENTS[@]}"; do

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

BASQUET_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "BASQUET value: ${BASQUET_VALUE} (${BASQUET_STATUS})"

}

sw_module_run() {

    sw_state_use "basquet"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    sw_state_clear

    BASQUET_collect

    BASQUET_analyze

    sw_status_update "${BASQUET_STATUS}" || return 1

    BASQUET_update_state

    sw_state_save

    BASQUET_report

    # Optional: append to CSV history for sparkline widgets.
    #
    # sw_csv_append \
    #     "BASQUET" \
    #     "value" \
    #     "${BASQUET_VALUE}"

}
