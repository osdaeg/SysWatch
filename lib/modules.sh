#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Module handling
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

sw_list_modules() {

    shopt -s nullglob

    local modules=("${MODULES_DIR}"/*.sh)

    shopt -u nullglob

    printf '%s\n' "${modules[@]}"

}

sw_module_should_run() {

    local module="$1"
    local interval="$2"

    local stamp="${STATE_DIR}/.${module}.last_run"

    #
    # Nunca ejecutado
    #

    [[ ! -f "${stamp}" ]] && return 0

    local now
    local last

    now=$(date +%s)
    last=$(<"${stamp}")

    (( now - last >= interval ))

}

sw_module_touch() {

    local module="$1"

    date +%s > "${STATE_DIR}/.${module}.last_run"

}

sw_run_module() {

    local module="$1"

    [[ -f "${module}" ]] || return 1

    sw_log_info "Modules" "Loading $(basename "${module}")"

    (

        source "${module}"

        if ! declare -F sw_module_run >/dev/null; then

            sw_log_warning \
                "Modules" \
                "Module $(basename "${module}") does not define sw_module_run()"

            exit 1

        fi

        sw_module_global_config_load "${MODULE_NAME}"
    
        if sw_module_should_run "${MODULE_NAME}" "${MODULE_INTERVAL}"
        then

            sw_module_run

            sw_module_touch "${MODULE_NAME}"

            sw_module_global_config_save "${MODULE_NAME}" "${MODULE_INTERVAL}" "${MODULE_ORDER}" "${MODULE_REMOTE}"
            
        else
            sw_log_info \
                "${MODULE_NAME}" \
                "Skipping ${MODULE_NAME}"

        fi

    )

    local rc=$?

    sw_log_debug \
        "Modules" \
        "Finished $(basename "${module}") (rc=${rc})"

    return "${rc}"

}

sw_run_modules() {

    local module
    local count=0

    while IFS= read -r module; do

        [[ -n "${module}" ]] || continue

        if sw_run_module "${module}"; then

            ((++count))

        else

            sw_log_error \
                "Modules" \
                "Module $(basename "${module}") failed"

        fi

    done < <(sw_list_modules)

    sw_log_info \
        "Modules" \
        "Executed ${count} module(s)"

}