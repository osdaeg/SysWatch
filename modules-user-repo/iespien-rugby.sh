#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# module RUGBY
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

readonly MODULE_NAME="IESPIEN-RUGBY"
readonly MODULE_DESCRIPTION="RUGBY events"
readonly MODULE_VERSION="0.1.0"

MODULE_INTERVAL=${MODULE_INTERVAL:-21400}
MODULE_ORDER=${MODULE_ORDER:-9999}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly RUGBY_WARNING="${RUGBY_WARNING:-80}"
readonly RUGBY_CRITICAL="${RUGBY_CRITICAL:-95}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

RUGBY_VALUE=0
RUGBY_STATUS="${SW_STATUS_UNKNOWN}"
RUGBY_EVENTS=()

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

RUGBY_collect() {

    local anio mes dia
    local file cached item
    local competicion contrincantes fecha hora escenario canales

    anio=$(date +%Y)
    mes=$(date +%m)
    dia=$(date +%d)

    file="/home/daniel/docker/util/iespien/cache/rugby_${anio}-${mes}-${dia}.json"

    [[ -f "$file" ]] || return 1

    sw_cache_copy "$file"

    cached=$(sw_cache_file "rugby_${anio}-${mes}-${dia}.json")

    [[ -f "$cached" ]] || return 1

    while IFS= read -r item; do

        competicion=$(jq -r '.competicion' <<<"$item")
        contrincantes=$(jq -r '.contrincantes' <<<"$item")
        fecha=$(jq -r '.fecha' <<<"$item")
        hora=$(jq -r '.hora' <<<"$item")
        escenario=$(jq -r '.escenario' <<<"$item")
        canales=$(jq -r '.canales | join(", ")' <<<"$item")

        RUGBY_EVENTS+=(
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

    #printf '%s\n' "${RUGBY_EVENTS[@]}"

}

RUGBY_analyze() {

    RUGBY_STATUS="${SW_STATUS_OK}"

    if ((RUGBY_VALUE >= RUGBY_CRITICAL)); then

        RUGBY_STATUS="${SW_STATUS_CRITICAL}"

    elif ((RUGBY_VALUE >= RUGBY_WARNING)); then

        RUGBY_STATUS="${SW_STATUS_WARNING}"

    fi

}

RUGBY_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata (consumed by lib/html.sh)
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "$(sw_translate "Rugby")"
    sw_state_set "module.icon" "sports/rugby"
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

    for data in "${RUGBY_EVENTS[@]}"; do

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

RUGBY_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "RUGBY value: ${RUGBY_VALUE} (${RUGBY_STATUS})"

}

sw_module_run() {

    sw_state_use "rugby"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    sw_state_clear

    RUGBY_collect

    RUGBY_analyze

    sw_status_update "${RUGBY_STATUS}" || return 1

    RUGBY_update_state

    sw_state_save

    RUGBY_report

    # Optional: append to CSV history for sparkline widgets.
    #
    # sw_csv_append \
    #     "RUGBY" \
    #     "value" \
    #     "${RUGBY_VALUE}"

}
