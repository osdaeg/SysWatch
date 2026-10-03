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

function sw_zodiac_emoji() {

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


    if [[ -z "${REMOTES//+([ ,])}" ]]; then
        echo "La variable REMOTES está vacía o no es válida. Saltando creación."
    else
   
        IFS=',' read -ra CARPETAS <<< "$REMOTES"

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

    for csv in "${IMPORT_DIR}"/*.csv; do
        [[ -f "${csv}" ]] || continue

        filename="${csv##*/}"

        remote_module="${filename%%.*}"
        metric="${filename#*.}"
        metric="${metric%.csv}"

        mkdir -p "${CSV_DIR}/${remote_module}"

        mv "${csv}" \
            "${CSV_DIR}/${remote_module}/${metric}.csv"
    done

    # Mover archivos .state si existen
    if compgen -G "$IMPORT_DIR"/*.state > /dev/null; then
        sw_log_info "IMPORT" "$(ls ${IMPORT_DIR}/*.state)"
        mv "$IMPORT_DIR"/*.state "$STATE_DIR/"
    fi

    # Anexar y borrar archivos .timer si existen
    if compgen -G "$IMPORT_DIR"/*.timer > /dev/null; then
        [[ -d "$TIMER_DIR" ]] || mkdir -p "$TIMER_DIR"
        sw_log_info "IMPORT" "$(ls ${IMPORT_DIR}/*.timer)"
        cat "$IMPORT_DIR"/*.timer >> "$TIMER_DIR/timers.txt" && rm "$IMPORT_DIR"/*.timer
    fi
    
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

    command -v "$cmd" >/dev/null 2>&1 \
        || sw_die "Required command not found: ${cmd}"

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
