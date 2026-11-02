#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Configuration handling
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

#
# Load module configuration
#
# Usage:
#   sw_config_load weather
#

sw_module_global_config_check() {

    if [[ ! -f "$PROJECT_DIR/config/modules.conf" ]]; then
        if ! sw_is_root; then
            touch "$PROJECT_DIR/config/modules.conf"
        else
            return 1
        fi
    fi

    return 0

}

sw_module_global_config_load() {

    local module=$1
    local line=""
    local values=""

    if ! declare -p MODULE_ORDER &>/dev/null; then
        MODULE_ORDER=""
    fi

    if ! declare -p MODULE_REMOTE &>/dev/null; then
        MODULE_REMOTE=""
    fi

    if ! declare -p MODULE_INTERVAL &>/dev/null; then
        MODULE_INTERVAL=""
    fi

    if ! declare -p MODULE_INTERVAL_NORMAL &>/dev/null; then
        MODULE_INTERVAL_NORMAL=""
    fi

    if ! declare -p MODULE_INTERVAL_ALT &>/dev/null; then
        MODULE_INTERVAL_ALT=""
    fi

    if sw_module_global_config_check; then
        line=$(grep "^${module}=" "$PROJECT_DIR/config/modules.conf")

        if [ -n "$line" ]; then
            values="${line#${module}=}"

            IFS="|" read -r val1 val2 val3 val4 val5 <<<"$values"

            [[ -n "$val1" ]] && MODULE_INTERVAL="$val1"
            [[ -n "$val2" ]] && MODULE_INTERVAL_NORMAL="$val2"
            [[ -n "$val3" ]] && MODULE_INTERVAL_ALT="$val3"
            [[ -n "$val4" ]] && MODULE_ORDER="$val4"
            [[ -n "$val5" ]] && MODULE_REMOTE="$val5"
        fi

    else
        return 1
    fi

    return 0
}

sw_module_global_config_save() {

    local module=$1
    local interval=$2
    local interval_normal=$3
    local interval_alt=$4
    local order=$5
    local remote=$6

    local chain="${interval}|${interval_normal}|${interval_alt}|${order}|${remote}"

    local file="$PROJECT_DIR/config/modules.conf"

    if grep -q "^${module}=" "$file"; then
        sed -i "s#^${module}=.*#${module}=${chain}#" "$file"
    else
        echo "${module}=${chain}" >>"$file"
    fi

    return 0

}

sw_module_load_config() {

    local module="$1"

    [[ -z "${module}" ]] && return 1

    local file="${PROJECT_DIR}/config/${module}.conf"

    [[ -f "${file}" ]] || return 0

    # shellcheck disable=SC1090
    source "${file}"

}

sw_module_save_config() {

    local module="$1"
    local content="$2"
    local file="${PROJECT_DIR}/config/${module}.conf"
    local tmp_file

    [[ -z "${module}" ]] && return 1

    mkdir -p "${PROJECT_DIR}/config" || return 1

    tmp_file="$(mktemp "${file}.XXXXXX")" || return 1

    if ! printf '%s\n' "${content}" >"${tmp_file}"; then
        rm -f -- "${tmp_file}"
        return 1
    fi

    if ! mv -f -- "${tmp_file}" "${file}"; then
        rm -f -- "${tmp_file}"
        return 1
    fi

}

sw_module_get_config() {

    local key="$1"
    local default="$2"

    local value="${!key:-}"

    printf '%s\n' "${value:-${default}}"

}

sw_load_config() {

    local env_file="${PROJECT_DIR}/.env"

    if [[ -f "$env_file" ]]; then
        source "$env_file" ||
            sw_die "Unable to load configuration from ${env_file}"
    fi

    # -------------------------------------------------------------------------
    # General
    # -------------------------------------------------------------------------

    : "${LOG_LEVEL:=INFO}"
    : "${HOSTNAME_ALIAS:=$(hostname)}"

    # -------------------------------------------------------------------------
    # Notifications
    # -------------------------------------------------------------------------

    : "${ENABLE_GOTIFY:=false}"
    : "${GOTIFY_URL:=}"
    : "${GOTIFY_TOKEN:=}"

    # -------------------------------------------------------------------------
    # HTML
    # -------------------------------------------------------------------------

    : "${HTML_TITLE:=SysWatch}"

    # -------------------------------------------------------------------------
    # Directories
    # -------------------------------------------------------------------------

    : "${STATE_DIR:=${PROJECT_DIR}/state}"
    : "${LOG_DIR:=${PROJECT_DIR}/logs}"
    : "${CACHE_DIR:=${PROJECT_DIR}/cache}"
    : "${HTML_DIR:=${PROJECT_DIR}/html}"
    : "${LOCK_DIR:=${PROJECT_DIR}/locks}"

}

sw_check_config() {

    if [[ "${ENABLE_GOTIFY}" == "true" ]]; then

        [[ -n "${GOTIFY_URL}" ]] ||
            sw_die "Missing GOTIFY_URL"

        [[ -n "${GOTIFY_TOKEN}" ]] ||
            sw_die "Missing GOTIFY_TOKEN"

    fi

}
