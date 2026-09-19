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
        "$REMOTE_DIR"
        
    sw_create_remote_dirs    

    sw_lock_acquire "syswatch_user"

    sw_log_rename
    
    sw_log_execution

    sw_log_info "${LAUNCHER_NAME}" "SysWatch started"

    sw_log_info "${LAUNCHER_NAME}" "Loading modules"

    sw_run_modules

    sw_timer_update_all

    for entry in "${SW_TIMER_DONE[@]}"; do

        modulo="${entry%%:*}"
        action="${entry#*:}"

        sw_state_use "${modulo}"

        case "${action}" in

            deletestate)
                sw_state_delete
                echo "$(date) (main) ${modulo} ${action}" >> ~/scripts/syswatch/timer.txt
                ;;
            statusok)
                sw_state_load
                sw_status_update "OK"
                sw_state_save
                ;;
            statuswarning)
                sw_state_load
                sw_status_update "WARNING"
                sw_state_save
                ;;
            statuscritical)
                sw_state_load
                sw_status_update "CRITICAL"
                sw_state_save
                ;;
        
        esac

    done

    sw_import

    sw_log_info "${LAUNCHER_NAME}" "Updating HTML"

    sw_html_generate

    sw_log_info "${LAUNCHER_NAME}" "SysWatch finished"

}

main "$@"
