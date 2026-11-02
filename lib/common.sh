#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# funciones comunes a todos los scripts de syswatch
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

set -o errexit
set -o pipefail
set -o nounset

# -----------------------------------------------------------------------------
# Global variables
# -----------------------------------------------------------------------------

readonly SW_VERSION="0.1.0"
readonly PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LIB_DIR="${PROJECT_DIR}/lib"
readonly CONFIG_DIR="${PROJECT_DIR}/config"
: "${STATE_DIR:=${PROJECT_DIR}/state}"
: "${LOG_DIR:=${PROJECT_DIR}/logs}"
: "${CACHE_DIR:=${PROJECT_DIR}/cache}"
: "${HTML_DIR:=${PROJECT_DIR}/html}"
: "${TIMER_DIR:=${PROJECT_DIR}/timer}"
: "${IMPORT_DIR:=${PROJECT_DIR}/import}"
: "${REMOTE_DIR:=${PROJECT_DIR}/remote}"
: "${HELPERS_DIR:=${PROJECT_DIR}/helpers}"
: "${TRANSLATIONS_DIR:=${PROJECT_DIR}/translations}"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Country flags
# -----------------------------------------------------------------------------

declare -gA SW_COUNTRY_FLAGS=()

sw_country_flags_load() {

    local -a fields
    local country
    local official
    local iso
    local flag
    local key

    SW_COUNTRY_FLAGS=()

    sw_cache_exists "countries.map" || return 0

    while IFS='|' read -r -a fields; do

        country="${fields[0]:-}"

        [[ -n "${country}" ]] || continue

        # Support both formats:
        #
        # OpenSky name | ISO | flag
        # OpenSky name | official name | ISO | flag

        if ((${#fields[@]} >= 4)); then
            official="${fields[1]:-}"
            iso="${fields[2]:-}"
            flag="${fields[3]:-}"
        else
            official=""
            iso="${fields[1]:-}"
            flag="${fields[2]:-}"
        fi

        [[ -n "${flag}" ]] || continue

        for key in "$country" "$official" "$iso"; do

            [[ -n "${key}" ]] || continue

            key="${key,,}"
            SW_COUNTRY_FLAGS["${key}"]="${flag}"

        done

    done < <(sw_cache_read "countries.map")
}

sw_country_flag() {

    local country="${1,,}"

    [[ -n "${country}" ]] || return 0

    printf '%s' "${SW_COUNTRY_FLAGS[$country]:-}"
}

sw_zodiac_emoji() {

    declare -A zodiaco

    local signo=$1

    zodiaco=(
        ["Aries"]="♈"
        ["Taurus"]="♉"
        ["Gemini"]="♊"
        ["Cancer"]="♋"
        ["Leo"]="♌"
        ["Virgo"]="♍"
        ["Libra"]="♎"
        ["Scorpio"]="♏"
        ["Ophiuchus"]="⛎"
        ["Sagittarius"]="♐"
        ["Capricornus"]="♑"
        ["Aquarius"]="♒"
        ["Pisces"]="♓"
        ["Auriga"]=""
    )

    if [[ -n "${zodiaco[$signo]}" ]]; then
        echo "${zodiaco[$signo]}"
        return 0
    else
        return 1 # Error
    fi

}

sw_wait_unlocked() {
    local lock_file="${PROJECT_DIR}/lock"

    while [[ -e "$lock_file" ]]; do
        sleep 30
    done
}

sw_remote_export() {
    local source="$1"
    local destination="$2"
    local tmp

    [[ -f "$source" ]] || return 1

    # Temporal único en el mismo directorio NFS.
    tmp="${destination}.tmp.$$.$RANDOM"

    if ! cat -- "$source" >"$tmp"; then
        rm -f -- "$tmp"
        sw_log "ERROR" "No se pudo escribir el temporal remoto: $tmp"
        return 1
    fi

    if ! mv -f -- "$tmp" "$destination"; then
        sw_log "ERROR" "No se pudo publicar el archivo remoto: $destination"
        return 1
    fi

    return 0
}

sw_check_remote() {

    local timeout=$1
    local remote=$2

    if ! read -t "$timeout" < <(
        stat -t "$remote" 2>/dev/null
    ); then
        return 1
    fi
}

sw_create_remote_dirs() {

    shopt -s extglob

    if [[ -z "${REMOTES//+([ ,])/}" ]]; then
        echo "La variable REMOTES está vacía o no es válida. Saltando creación."
    else

        IFS=',' read -ra CARPETAS <<<"$REMOTES"

        for carpeta in "${CARPETAS[@]}"; do

            if [[ -n "$carpeta" ]]; then
                mkdir -p "$REMOTE_DIR/$carpeta"
            fi
        done
    fi

    shopt -u extglob
}

sw_sanitize_state_value() {
    printf '%s' "$1" |
        tr '\r\n\t' ' ' |
        tr -s ' '
}

sw_import() {
    # Crear IMPORT_DIR si no existe
    [[ -d "$IMPORT_DIR" ]] || mkdir -p "$IMPORT_DIR"
    [[ -f "$IMPORT_DIR/.import" ]] || touch "$IMPORT_DIR/.import"

    local csv filename remote_module metric
    local state timer local_module line existing_module
    local message

    # Importar CSV normales y ocultos.
    # Se excluyen archivos temporales.
    for csv in "$IMPORT_DIR"/*.csv "$IMPORT_DIR"/.[!.]*.csv "$IMPORT_DIR"/..?*.csv; do
        [[ -f "$csv" ]] || continue
        [[ "$csv" == *.tmp.* ]] && continue

        filename="${csv##*/}"

        remote_module="${filename%%.*}"
        metric="${filename#*.}"
        metric="${metric%.csv}"

        # Para nombres ocultos como .snapshots.cpu.csv:
        # módulo=.snapshots, métrica=cpu
        if [[ "$filename" == .* ]]; then
            remote_module="${filename#.}"
            remote_module="${remote_module%%.*}"
            metric="${filename#*.}"
            metric="${metric#*.}"
            metric="${metric%.csv}"
        fi

        mkdir -p "${CSV_DIR}/${remote_module}"

        mv -- "$csv" "${CSV_DIR}/${remote_module}/${metric}.csv"
    done

    # Importar estados normales y ocultos.
    for state in "$IMPORT_DIR"/*.state "$IMPORT_DIR"/.[!.]*.state "$IMPORT_DIR"/..?*.state; do
        [[ -f "$state" ]] || continue
        [[ "$state" == *.tmp.* ]] && continue

        sw_log_info "IMPORT" "$state"
        mv -- "$state" "$STATE_DIR/"
    done

    # Importar timers, reemplazando los existentes.
    [[ -d "$TIMER_DIR" ]] || mkdir -p "$TIMER_DIR"

    for timer in "$IMPORT_DIR"/*.timer "$IMPORT_DIR"/.[!.]*.timer "$IMPORT_DIR"/..?*.timer; do
        [[ -f "$timer" ]] || continue
        [[ "$timer" == *.tmp.* ]] && continue

        local_module="${timer##*/}"
        local_module="${local_module%.timer}"

        if [[ -f "$TIMER_DIR/timers.txt" ]]; then
            while IFS= read -r line; do
                existing_module="${line%%=*}"
                [[ "$existing_module" == "$local_module" ]] && continue
                printf '%s\n' "$line"
            done <"$TIMER_DIR/timers.txt" >"$TIMER_DIR/timers.tmp"

            mv "$TIMER_DIR/timers.tmp" "$TIMER_DIR/timers.txt"
        fi

        if cat "$timer" >>"$TIMER_DIR/timers.txt"; then
            rm -f -- "$timer"
        fi
    done

    # Importar mensajes normales y ocultos.
    for message in "$IMPORT_DIR"/*.message "$IMPORT_DIR"/.[!.]*.message "$IMPORT_DIR"/..?*.message; do
        [[ -f "$message" ]] || continue
        [[ "$message" == *.tmp.* ]] && continue

        mv -- "$message" "$CACHE_DIR/"
    done
}

sw_download() {

    local url="$1"
    local output="$2"

    shift 2

    curl \
        --silent \
        --show-error \
        --fail \
        --location \
        "$@" \
        --output "${output}" \
        "${url}"

}

sw_human_bytes() {

    numfmt \
        --to=iec-i \
        --suffix=B \
        "$1"

}

sw_timestamp() {

    date '+%Y-%m-%d %H:%M:%S'

}

sw_lock_acquire() {

    local name="$1"

    exec 9>"${LOCK_DIR}/${name}.lock"

    flock -n 9 || {

        sw_log_warning \
            "Lock" \
            "Another '${name}' instance is already running."

        exit 0

    }

}

sw_timestamp_file() {

    date '+%Y%m%d_%H%M%S'

}

sw_die() {

    printf 'ERROR: %s\n' "$*" >&2

    exit 1

}

sw_require_command() {

    local cmd="$1"

    command -v "$cmd" >/dev/null 2>&1 ||
        sw_die "Required command not found: ${cmd}"

}

sw_mkdir() {

    [[ $# -gt 0 ]] || return 0

    mkdir -p "$@"

}

sw_script_dir() {

    cd -- "$(dirname -- "${BASH_SOURCE[1]}")" && pwd -P

}

sw_is_root() {

    [[ $EUID -eq 0 ]]

}

sw_format_number() {

    printf "%.0f" "$1" | sed ':a;s/\B[0-9]\{3\}\>/.&/;ta'

}
