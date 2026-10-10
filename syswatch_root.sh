#!/usr/bin/env bash

trap 'sw_log_critical "${LAUNCHER_NAME}" "Unexpected error on line ${LINENO}"' ERR

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

set -o errexit
set -o pipefail
set -o nounset

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LAUNCHER_NAME="ROOT Launcher"


# -----------------------------------------------------------------------------
# Load libraries
# -----------------------------------------------------------------------------
source "${SCRIPT_DIR}/lib/common.sh"
readonly MODULES_DIR="${PROJECT_DIR}/modules-root"

source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/logger.sh"
source "${LIB_DIR}/state.sh"
source "${LIB_DIR}/modules.sh"
source "${LIB_DIR}/events.sh"
source "${LIB_DIR}/notify.sh"
source "${LIB_DIR}/status.sh"
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

    sw_translations_load
        
    sw_lock_acquire "syswatch_root"    

    sw_log_execution

    sw_log_info "${LAUNCHER_NAME}" "SysWatch started"

    sw_log_info "${LAUNCHER_NAME}" "Loading modules"

    sw_run_modules

    # sw_log_info "${LAUNCHER_NAME}" "Updating HTML"

    # sw_generate_html

    sw_translations_save

    sw_log_info "${LAUNCHER_NAME}" "SysWatch finished"

}

main "$@"
