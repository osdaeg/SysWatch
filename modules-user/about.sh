#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# about module
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="About"
readonly MODULE_DESCRIPTION="System information"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-100}
MODULE_REMOTE=${MODULE_REMOTE:-""}


# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

ABOUT_DISTRIBUTION=""
ABOUT_KERNEL=""
ABOUT_CPU=""
ABOUT_GPU=""
ABOUT_MEMORY=""
ABOUT_ARCH=""


# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

about_get_icon() {

    case "${ID:-}" in

        debian)
            echo "distros/debian"
            ;;

        ubuntu)
            echo "distros/ubuntu"
            ;;

        arch)
            echo "distros/arch"
            ;;

        rocky)
            echo "distros/rocky"
            ;;

        rhel)
            echo "distros/redhat"
            ;;

        fedora)
            echo "distros/fedora"
            ;;

        linuxmint)
            echo "distros/mint"
            ;;

        opensuse*|sles)
            echo "distros/suse"
            ;;

        mx)
            echo "distros/mx"
            ;;

        *)
            echo "lucide/monitor-pc"
            ;;

    esac

}

about_collect() {

    # Distribution

    if [[ -r /etc/os-release ]]; then

        # shellcheck disable=SC1091
        source /etc/os-release

        ABOUT_DISTRIBUTION="${PRETTY_NAME:-${NAME:-Unknown}}"

    else

        ABOUT_DISTRIBUTION="Unknown"

    fi


    # Kernel

    ABOUT_KERNEL="$(uname -r 2>/dev/null || echo "Unknown")"


    # Architecture

    ABOUT_ARCH="$(uname -m 2>/dev/null || echo "Unknown")"


    # CPU

    ABOUT_CPU="$(
        awk -F: '
            /^model name/ {
                gsub(/^[ \t]+/, "", $2)
                print $2
                exit
            }
        ' /proc/cpuinfo 2>/dev/null
    )"

    [[ -z "$ABOUT_CPU" ]] && ABOUT_CPU="Unknown"


    # GPU

    ABOUT_GPU=""

    if command -v lspci >/dev/null 2>&1; then

        ABOUT_GPU="$(
            lspci 2>/dev/null |
            awk -F': ' '
                /VGA compatible controller|3D controller|Display controller/ {
                    print $2
                    exit
                }
            '
        )"

    fi

    [[ -z "$ABOUT_GPU" ]] && ABOUT_GPU="Unknown"


    # Memory

    local memory_kib

    memory_kib="$(
        awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null
    )"

    if [[ "$memory_kib" =~ ^[0-9]+$ ]]; then

        ABOUT_MEMORY="$(
            awk -v kib="$memory_kib" '
                BEGIN {
                    gib = kib / 1024 / 1024
                    if (gib >= 1)
                        printf "%.2f GiB", gib
                    else
                        printf "%.0f MiB", kib / 1024
                }
            '
        )"

    else

        ABOUT_MEMORY="Unknown"

    fi

}


about_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "$(sw_translate "About")"
    sw_state_set "module.icon" "$(about_get_icon)"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Data
    # -------------------------------------------------------------------------

    sw_state_set "distribution" "${ABOUT_DISTRIBUTION}"
    sw_state_set "distribution.label" "$(sw_translate "Distribution")"
    sw_state_set "distribution.widget" "value"
    sw_state_set "distribution.order" "10"

    sw_state_set "kernel" "${ABOUT_KERNEL}"
    sw_state_set "kernel.label" "$(sw_translate "Kernel")"
    sw_state_set "kernel.widget" "value"
    sw_state_set "kernel.order" "20"

    sw_state_set "cpu" "${ABOUT_CPU}"
    sw_state_set "cpu.label" "$(sw_translate "CPU")"
    sw_state_set "cpu.widget" "value"
    sw_state_set "cpu.order" "30"

    sw_state_set "gpu" "${ABOUT_GPU}"
    sw_state_set "gpu.label" "$(sw_translate "GPU")"
    sw_state_set "gpu.widget" "value"
    sw_state_set "gpu.order" "40"

    sw_state_set "memory" "${ABOUT_MEMORY}"
    sw_state_set "memory.label" "$(sw_translate "Memory")"
    sw_state_set "memory.widget" "value"
    sw_state_set "memory.order" "50"

    sw_state_set "architecture" "${ABOUT_ARCH}"
    sw_state_set "architecture.label" "$(sw_translate "Architecture")"
    sw_state_set "architecture.widget" "value"
    sw_state_set "architecture.order" "60"

}


about_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "System: ${ABOUT_DISTRIBUTION}; Kernel: ${ABOUT_KERNEL}; CPU: ${ABOUT_CPU}; GPU: ${ABOUT_GPU}; Memory: ${ABOUT_MEMORY}; Architecture: ${ABOUT_ARCH}"

}


sw_module_run() {

    sw_state_use "about"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    about_collect

if sw_cache_exists "about.txt"; then

    local file="$(sw_cache_file "about.txt")"

    local timestamp_saved="$(cat "$file")"
    local date_saved="$(date -d "@$timestamp_saved" +%Y-%m-%d)"
    local date_today="$(date +%Y-%m-%d)"

    if [[ "$date_saved" != "$date_today" ]]; then
        sw_status_update "${SW_STATUS_INFO}" || return 1
        MODULE_INTERVAL=300
    else
        sw_status_update "${SW_STATUS_OK}" || return 1
        MODULE_INTERVAL=6000
    fi

    echo "$(date +%s)" > "$file"

else

    sw_status_update "${SW_STATUS_INFO}" || return 1

    echo "$(date +%s)" > "$(sw_cache_file "about.txt")"

    MODULE_INTERVAL=300

fi

    about_update_state

    sw_state_save

    about_report

}