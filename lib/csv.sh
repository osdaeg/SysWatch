#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# CSV historical storage
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly CSV_DIR="${PROJECT_DIR}/csv"

readonly CSV_MAX_LINES="${CSV_MAX_LINES:-1000}"

# -----------------------------------------------------------------------------
# Internal
# -----------------------------------------------------------------------------

sw_csv_last_max() {
    local module="$1"
    local key="$2"
    local samples="${3:-10}"

    sw_csv_last_values "$module" "$key" "$samples" |
        sort -nr |
        head -1
}

# -----------------------------------------------------------------------------
#
# sw_csv_all_above <category> <metric> <threshold> <samples>
#
# True only if there are at least <samples> prior readings AND every one of
# them is >= <threshold>. Intended to be combined with the current reading
# in a module's analyze() step, e.g.:
#
#   if (( CPU_USAGE >= CPU_CRITICAL )) &&
#      sw_csv_all_above cpu usage "${CPU_CRITICAL}" "${CPU_SUSTAINED_SAMPLES}"
#   then
#       CPU_STATUS="${SW_STATUS_CRITICAL}"
#   fi
#
# This means a single spike never flips the status (and therefore never
# fires an event or a notification): the condition has to hold for the
# current reading AND the <samples> readings before it.
#
# Note: sw_csv_append() for the current reading should happen AFTER
# analyze() runs (this is already the case in cpu.sh/memory.sh/network.sh),
# so "prior readings" here never includes the value being evaluated right
# now.
#
# -----------------------------------------------------------------------------

sw_csv_all_above() {

    local category="$1"
    local metric="$2"
    local threshold="$3"
    local samples="$4"

    local values
    local count=0
    local v

    mapfile -t values < <(sw_csv_last_values "${category}" "${metric}" "${samples}")

    (( ${#values[@]} >= samples )) || return 1

    for v in "${values[@]}"
    do

        [[ -n "${v}" ]] || return 1

        (( v >= threshold )) || return 1

        (( count++ ))

    done

    (( count == samples ))

}

sw_csv_filename() {

    local category="$1"
    local metric="$2"

    mkdir -p "${CSV_DIR}/${category}"

    printf "%s/%s/%s.csv" \
        "${CSV_DIR}" \
        "${category}" \
        "${metric}"

}

# -----------------------------------------------------------------------------

sw_csv_last_values() {

    local category="$1"
    local metric="$2"
    local samples="${3:-10}"

    local file

    file="$(sw_csv_filename "${category}" "${metric}")"

    [[ -f "${file}" ]] || return

    tail -n +2 "${file}" |
        tail -n "${samples}" |
        cut -d',' -f2

}

sw_csv_append() {

    local category="$1"
    local metric="$2"
    local value="$3"

    [[ -z "${value}" ]] && return

    local file

    file="$(sw_csv_filename "${category}" "${metric}")"

    #
    # Create header
    #

    if [[ ! -f "${file}" ]]; then

        echo "timestamp,value" > "${file}"

    fi

    printf "%s,%s\n" \
        "$(date +%s)" \
        "${value}" \
        >> "${file}"

    sw_csv_trim \
        "${file}" \
        "${CSV_MAX_LINES:-288}"

}

# -----------------------------------------------------------------------------

sw_csv_trim() {

    local file="$1"
    local max_lines="${2:-288}"

    local lines

    lines=$(wc -l < "${file}")

    (( lines <= CSV_MAX_LINES + 1 )) && return

    {

        head -n1 "${file}"

        tail -n "${CSV_MAX_LINES}" "${file}"

    } > "${file}.tmp"

    mv "${file}.tmp" "${file}"

}

# -----------------------------------------------------------------------------

sw_csv_last() {

    local category="$1"
    local metric="$2"

    local file

    file="$(sw_csv_filename "${category}" "${metric}")"

    [[ -f "${file}" ]] || return

    tail -n1 "${file}"

}

sw_csv_export_remote() {
    local module="$1"
    local remote_dir="$2"
    local remote_module="$3"

    local source_dir="${CSV_DIR}/${module}"
    local csv
    local metric

    [[ -d "${source_dir}" ]] || return 0

    for csv in "${source_dir}"/*.csv; do
        [[ -f "${csv}" ]] || continue

        metric="${csv##*/}"
        metric="${metric%.csv}"

        cp "${csv}" \
            "${remote_dir}/${remote_module}.${metric}.csv"

    done
}