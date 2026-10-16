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
SW_STATE_REMOTE=false

SW_STATE_MODULE_PREVIOUS=""
SW_STATE_REMOTE_PREVIOUS=false
STATE_DIR_PREVIOUS=""

SW_STATE_REMOTE_FILE=""
SW_STATE_REMOTE_DIR=""

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

    local base="${1:-}"
    local key
    local suffix

    [[ -n "$base" ]] || return 1

    local -a modifiers=(
        label display widget unit warning critical order
        hidden scale min max history render align color
        from persist
    )

    for key in "${!SW_STATE[@]}"; do

        [[ "$key" == "$base" ]] && {
            unset 'SW_STATE[$key]'
            continue
        }

        for suffix in "${modifiers[@]}"; do
            if [[ "$key" == "$base.$suffix" ]]; then
                unset 'SW_STATE[$key]'
                break
            fi
        done
    done
}

sw_state_use() {

    SW_STATE_MODULE="$1"

}

sw_state_remote() {

    local remote=$1
    
    if [ -n "$remote" ] && [ -d "${REMOTE_DIR}/$remote" ]; then
    
        if sw_check_remote 3 "${REMOTE_DIR}/$remote"; then
            
            SW_STATE_REMOTE_DIR="${REMOTE_DIR}/$remote"
            SW_STATE_REMOTE=true
            SW_STATE_REMOTE_FILE="${SW_STATE_REMOTE_DIR}/${SW_STATE_MODULE}-${HOSTNAME_ALIAS}.state"
            SW_STATE_MODULE_PREVIOUS=${SW_STATE_MODULE}
    
        else
        
            SW_STATE_REMOTE=false
            SW_STATE_REMOTE_DIR=
            SW_STATE_REMOTE_FILE=
        fi
       
    else
       return 1
    fi
}

sw_state_restore() {

    SW_STATE_MODULE="$SW_STATE_MODULE_PREVIOUS"
    SW_STATE_REMOTE=false

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

sw_state_append_hostname() {

    sw_state_set "sw_hostname" "$HOSTNAME_ALIAS"
    sw_state_set "sw_hostname.label" "Host"
    sw_state_set "sw_hostname.order" "1000"
    sw_state_set "sw_hostname.hidden" "true"
    
}

sw_state_temporal_copy() {

    mv "$SW_STATE_REMOTE_DIR"/*.csv "$IMPORT_DIR"

    mv "$SW_STATE_REMOTE_FILE" "$IMPORT_DIR"
    mv "$SW_STATE_REMOTE_DIR/$SW_STATE_MODULE-$HOSTNAME_ALIAS.timer" "$IMPORT_DIR"
 
    
    
}

sw_state_save() {

    local file
    local key
    local total
    
    sw_state_append_hostname
    
    if [ "$SW_STATE_REMOTE" == "true" ]; then
    
        sw_state_set "sw_hostname.hidden" "false"
        
        
        
    else
    
         sw_state_set "sw_hostname.hidden" "true"
        
    fi

    file="$(sw_state_file)"

    sw_mkdir "${STATE_DIR}"

    : > "${file}"
    
    #echo "$SW_STATE_MODULE|$file|$STATE_DIR" >> ~/scripts/syswatch/problemas.txt

    while IFS= read -r key; do

        printf '%s=%s\n' \
            "${key}" \
            "${SW_STATE[${key}]}"

    done < <(
        printf '%s\n' "${!SW_STATE[@]}" | sort
    ) >> "${file}"
    
    if [ "$SW_STATE_REMOTE" == "true" ]; then

        if [[ -f "$SW_STATE_REMOTE_DIR/.import" ]]; then
    
             cp "$file" "$SW_STATE_REMOTE_FILE"

             total=$(sw_timer_from_module)
        
             sw_timer_create_raw "$SW_STATE_MODULE-$HOSTNAME_ALIAS" "$SW_STATE_REMOTE_DIR" "$total" "deletestate"

             sw_state_temporal_copy

             sw_csv_export_remote \
                "${SW_STATE_MODULE}" \
                "${SW_STATE_REMOTE_DIR}" \
                "${SW_STATE_MODULE}-${HOSTNAME_ALIAS}"
        fi    
           
    fi
    
    

   # sw_state_restore

}

sw_state_delete() {

    local file
    file="$(sw_state_file)"

    rm -f "${file}"
}

sw_state_reset() {

    > "$(sw_state_file)"

}

sw_state_clear() {

    SW_STATE=()

}
