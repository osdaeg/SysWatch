#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# module futbol
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

readonly MODULE_NAME="IESPIEN-Fútbol"
readonly MODULE_DESCRIPTION="futbol events"
readonly MODULE_VERSION="0.1.0"

MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-10}
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

    file="/home/daniel/docker/util/iespien/cache/fútbol_${anio}-${mes}-${dia}.json"

    [[ -f "$file" ]] || return 1

    sw_cache_copy "$file"

    cached=$(sw_cache_file "fútbol_${anio}-${mes}-${dia}.json")

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

    sw_state_set "module.label" "$(sw_translate "Football")"
    sw_state_set "module.icon" "sports/futbol"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Data
    # -------------------------------------------------------------------------

    local data

    local competicion contrincantes fecha hora escenario canales
    local row=1
    local competition=0
    local order=10
    local previous="previo"
    local event

    for data in "${FUTBOL_EVENTS[@]}"; do

        IFS='|' read -r competicion contrincantes fecha hora escenario canales <<<"$data"

        event=""

        [[ -n "$contrincantes" ]] && event="${contrincantes}"
        [[ -n "$fecha" ]] && event+="${event:+ - }${fecha}"
        [[ -n "$hora" ]] && event+="${event:+ - }${hora}"
        [[ -n "$escenario" ]] && event+="${event:+ - }${escenario}"
        [[ -n "$canales" ]] && event+="${event:+ - }${canales}"

        if [[ "$competicion" != "$previous" ]]; then

            ((competition++))

            sw_state_set "competicion${competition}" "$competicion"
            sw_state_set "competicion${competition}.label" "$(sw_translate "Competition")"
            sw_state_set "competicion${competition}.order" "$order"
            sw_state_set "competicion${competition}.color" "green"

            row=1
            previous="$competicion"
            ((order++))

            # La competición nueva se registra antes de escribir sus eventos.
            sw_state_set "evento${row}-${competition}" "$event"
            sw_state_set "evento${row}-${competition}.label" "$row"
            sw_state_set "evento${row}-${competition}.order" "$order"

        else

            sw_state_set "evento${row}-${competition}" "$event"
            sw_state_set "evento${row}-${competition}.label" "$row"
            sw_state_set "evento${row}-${competition}.order" "$order"

        fi

        echo "$competicion $competition $event $row"

        ((row++))
        ((order++))

    done

}

FUTBOL_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "futbol value: ${FUTBOL_VALUE} (${FUTBOL_STATUS})"

}

sw_module_run() {

    sw_state_use "futbol"

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
    #     "futbol" \
    #     "value" \
    #     "${FUTBOL_VALUE}"

}
