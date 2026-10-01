#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# updates module
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Updates"
readonly MODULE_DESCRIPTION="System updates module"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-3600}
MODULE_ORDER=${MODULE_ORDER:-1300}
MODULE_REMOTE=${MODULE_REMOTE:-""}


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly UPDATES_WARNING="${UPDATES_WARNING:-10}"
readonly UPDATES_CRITICAL="${UPDATES_CRITICAL:-25}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

UPDATES_TOTAL=0
UPDATES_MANAGER=""
UPDATES_STATUS="${SW_STATUS_UNKNOWN}"


# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

updates_collect_apt() {

    UPDATES_TOTAL=0

    if ! command -v apt >/dev/null 2>&1; then
        return 1
    fi

    mapfile -t updates < <(
        apt list --upgradable 2>/dev/null |
            tail -n +2 |
            grep -v '^$'
    )

    UPDATES_TOTAL="${#updates[@]}"

}


updates_collect_dnf() {

    UPDATES_TOTAL=0

    if ! command -v dnf >/dev/null 2>&1; then
        return 1
    fi

    UPDATES_TOTAL=$(
        dnf -q check-update 2>/dev/null |
            awk 'NF >= 3 && $1 !~ /^(Last|Obsoleting|$)/ { count++ } END { print count+0 }'
    )

}

updates_collect_zypper() {

    UPDATES_TOTAL=0

    if ! command -v zypper >/dev/null 2>&1; then
        return 1
    fi

    local output

    if ! output=$(zypper --non-interactive list-updates 2>/dev/null); then
        return 1
    fi

    UPDATES_TOTAL=$(
        awk -F'|' '
            /^[[:space:]]*v[[:space:]]*\|/ {
                count++
            }
            END {
                print count+0
            }
        ' <<< "$output"
    )
}

updates_collect_pacman() {

    UPDATES_TOTAL=0

    if ! command -v pacman >/dev/null 2>&1; then
        return 1
    fi

    local output
    local rc

    output=$(pacman -Qu 2>/dev/null)
    rc=$?

    if (( rc == 1 )) && [[ -z "$output" ]]; then
        # No hay actualizaciones.
        UPDATES_TOTAL=0
        return 0
    fi

    if (( rc != 0 )); then
        return 1
    fi

    UPDATES_TOTAL=$(wc -l <<< "$output")
}

updates_collect() {

    UPDATES_TOTAL=0
    UPDATES_MANAGER=""

    if [[ ! -r /etc/os-release ]]; then
        return 1
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    case "${ID:-}" in

        debian|ubuntu)

            UPDATES_MANAGER="apt"
            updates_collect_apt
            ;;

        fedora|rhel|rocky|almalinux|centos)

            UPDATES_MANAGER="dnf"
            updates_collect_dnf
            ;;

        opensuse*|sles)

            UPDATES_MANAGER="zypper"
            updates_collect_zypper
            ;;

        arch)

            UPDATES_MANAGER="pacman"
            updates_collect_pacman
            ;;

        *)

            return 1
            ;;

    esac

}


updates_analyze() {

    UPDATES_STATUS="${SW_STATUS_OK}"

    if (( UPDATES_TOTAL >= UPDATES_CRITICAL )); then

        UPDATES_STATUS="${SW_STATUS_CRITICAL}"

    elif (( UPDATES_TOTAL >= UPDATES_WARNING )); then

        UPDATES_STATUS="${SW_STATUS_WARNING}"

    elif (( UPDATES_TOTAL > 0 )); then

        UPDATES_STATUS="${SW_STATUS_INFO}"

    fi

}


updates_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata (consumed by lib/html.sh)
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "Updates"
    sw_state_set "module.icon" "lucide/package-check"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Data
    # -------------------------------------------------------------------------

    sw_state_set "total" "${UPDATES_TOTAL}"

    sw_state_set "total.label" "Updates"
    sw_state_set "total.widget" "number"
    sw_state_set "total.unit" ""
    sw_state_set "total.order" "10"
    sw_state_set "total.warning" "${UPDATES_WARNING}"
    sw_state_set "total.critical" "${UPDATES_CRITICAL}"

    sw_state_set "manager" "${UPDATES_MANAGER}"

}

updates_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Updates: ${UPDATES_TOTAL} (${UPDATES_STATUS})"

}


sw_module_run() {

    sw_state_use "updates"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    updates_collect || {

    sw_status_update "${SW_STATUS_UNKNOWN}" || return 1

    sw_state_set "manager" "${UPDATES_MANAGER}"
    sw_state_set "total" "0"

    sw_state_save

    sw_log_warning \
        "${MODULE_NAME}" \
        "Unable to query package manager"

    return 0
    }

    updates_analyze

    sw_status_update "${UPDATES_STATUS}" || return 1

    updates_update_state

    sw_state_save

    updates_report

}