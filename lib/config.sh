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

sw_module_load_config() {

    local module="$1"

    [[ -z "${module}" ]] && return 1

    local file="${PROJECT_DIR}/config/${module}.conf"

    [[ -f "${file}" ]] || return 0

    # shellcheck disable=SC1090
    source "${file}"

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
        source "$env_file" \
            || sw_die "Unable to load configuration from ${env_file}"
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

        [[ -n "${GOTIFY_URL}" ]] \
            || sw_die "Missing GOTIFY_URL"

        [[ -n "${GOTIFY_TOKEN}" ]] \
            || sw_die "Missing GOTIFY_TOKEN"

    fi

}