#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Persistent state handling
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# State context
# -----------------------------------------------------------------------------

SW_STATE_MODULE=""

declare -gA SW_STATE

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

sw_state_delete_prefix() {

    local prefix="${1:-}"
    local key

    [[ -n "$prefix" ]] || return 1

    for key in "${!SW_STATE[@]}"; do
        if [[ "$key" == "$prefix"* ]]; then
            unset "SW_STATE[$key]"
        fi
    done
}

sw_state_delete_key() {

    if [[ -z "${1:-}" ]]; then
        return 1
    fi

    local key_to_delete="$1"

    if [[ -v SW_STATE["$key_to_delete"] ]]; then
        unset "SW_STATE[$key_to_delete]"
    fi
}

sw_state_use() {

    SW_STATE_MODULE="$1"

}

sw_state_file() {

    printf '%s/%s.state\n' \
        "${STATE_DIR}" \
        "${SW_STATE_MODULE}"

}

sw_state_exists() {

    [[ -f "$(sw_state_file)" ]]

}

sw_state_load() {

    local file
    local key
    local value

    file="$(sw_state_file)"

    SW_STATE=()

    [[ -f "${file}" ]] || return 0

    while IFS='=' read -r key value; do

        [[ -n "${key}" ]] || continue

        SW_STATE["${key}"]="${value}"

    done < "${file}"

}

sw_state_get() {

    local key="$1"

    printf '%s\n' "${SW_STATE[${key}]-}"
    
    #echo "--${1}--" >> sw_state_get.txt

}

sw_state_set() {

    local key="$1"
    local value="$2"

    [[ -z "${value}" ]] && return 0

    SW_STATE["${key}"]="${value}"

}

sw_state_save() {

    local file
    local key

    file="$(sw_state_file)"

    sw_mkdir "${STATE_DIR}"

    : > "${file}"

    while IFS= read -r key; do

        printf '%s=%s\n' \
            "${key}" \
            "${SW_STATE[${key}]}"

    done < <(
        printf '%s\n' "${!SW_STATE[@]}" | sort
    ) >> "${file}"

}

sw_state_delete() {

    rm -f "$(sw_state_file)"

}

sw_state_reset() {

    > "$(sw_state_file)"

}

sw_state_clear() {

    SW_STATE=()

}
