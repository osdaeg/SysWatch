#!/usr/bin/env bash

trap 'sw_log_critical "${LAUNCHER_NAME}" "Unexpected error on line ${LINENO}"' ERR

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

set -o errexit
set -o pipefail
set -o nounset

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LAUNCHER_NAME="User Launcher"


# -----------------------------------------------------------------------------
# Load libraries
# -----------------------------------------------------------------------------
source "${SCRIPT_DIR}/lib/common.sh"
readonly MODULES_DIR="${PROJECT_DIR}/modules-user"

source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/logger.sh"
source "${LIB_DIR}/state.sh"
source "${LIB_DIR}/modules.sh"
source "${LIB_DIR}/events.sh"
source "${LIB_DIR}/notify.sh"
source "${LIB_DIR}/status.sh"
source "${LIB_DIR}/html.sh"
source "${LIB_DIR}/csv.sh"
source "${LIB_DIR}/cache.sh"
source "${LIB_DIR}/timer.sh"
source "${LIB_DIR}/translate.sh"
source "${LIB_DIR}/messages.sh"

# -----------------------------------------------------------------------------
# Initialize
# -----------------------------------------------------------------------------

sw_load_config
sw_check_config

main() {

    sw_mkdir \
        "$STATE_DIR" \
        "$LOG_DIR" \
        "$CACHE_DIR" \
        "${LOCK_DIR}" \
        "${CONFIG_DIR}" \
        "$HTML_DIR" \
        "$REMOTE_DIR" \
        "$TRANSLATIONS_DIR"
        
    sw_create_remote_dirs    

    sw_translations_load

    sw_lock_acquire "syswatch_user"

    sw_log_rename
    
    sw_log_execution

    sw_log_info "${LAUNCHER_NAME}" "SysWatch started"

    sw_log_info "${LAUNCHER_NAME}" "Loading modules"

    sw_run_modules

    sw_timer_update_all

    sw_state_clear

    printf '%s\n' "${SW_TIMER_DONE[@]}" >> ~/scripts/syswatch/timer.txt


    for entry in "${SW_TIMER_DONE[@]}"; do

        modulo="${entry%%:*}"
        action="${entry#*:}"

        echo "$(date) ENTRY=[$entry] MODULO=[$modulo] ACTION=[$action]" \
        >> ~/scripts/syswatch/timer.txt


        sw_state_use "${modulo}"

        case "${action}" in

            deletestate)
                sw_state_delete
                ;;
            statusok)
                sw_status_update_for "${modulo}" "${SW_STATUS_OK}"
                ;;
            statuswarning)
                sw_status_update_for "${modulo}" "${SW_STATUS_WARNING}"
                ;;
            statuscritical)
                sw_status_update_for "${modulo}" "${SW_STATUS_CRITICAL}"
                ;;
            statusinfo)
                sw_status_update_for "${modulo}" "${SW_STATUS_INFO}"
                ;;   
                            *)
                echo "$(date) CASE NO MATCH: [$action]" \
                    >> ~/scripts/syswatch/timer.txt
                ;;
        
        esac

    done

    sw_import

    sw_log_info "${LAUNCHER_NAME}" "Updating HTML"

    sw_html_generate

    sw_translations_save

    sw_log_info "${LAUNCHER_NAME}" "SysWatch finished"

}

main "$@"
