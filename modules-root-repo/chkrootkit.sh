#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# chkrootkit monitoring module
#
# Replaces rkhunter.sh (unmaintained upstream for 10+ years; chkrootkit
# ships a January 2026 release). Same architecture: chkrootkit runs on its
# OWN daily cron job, e.g.
#
#   0 3 * * * /usr/sbin/chkrootkit > /var/log/chkrootkit.log 2>&1
#
# and this module only reads that log -- it never invokes chkrootkit
# itself.
#
# chkrootkit's log has no summary section (unlike rkhunter's), so the
# signal here is simply counting how many check lines end in the literal
# words WARNING or INFECTED (chkrootkit prints "not infected" in
# lowercase for clean results and "INFECTED" in caps for a real hit, so
# matching the all-caps word specifically avoids false positives).
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Chkrootkit"
readonly MODULE_DESCRIPTION="chkrootkit log monitoring (does not run scans itself)"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-3660}
MODULE_ORDER=${MODULE_ORDER:-55}
MODULE_REMOTE=${MODULE_REMOTE:-""}


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly CHKROOTKIT_LOG="${CHKROOTKIT_LOG:-/var/log/chkrootkit/log.today.raw}"

# If the log hasn't been updated in this many hours, chkrootkit's own
# cron job may have stopped running -- flag it (unless something worse
# already did).
readonly CHKROOTKIT_MAX_AGE_HOURS="${CHKROOTKIT_MAX_AGE_HOURS:-36}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

CHKROOTKIT_WARNINGS=0
CHKROOTKIT_FALSE_POSITIVES=0
CHKROOTKIT_INFECTED=0
CHKROOTKIT_LOG_MTIME=0
CHKROOTKIT_LOG_AGE_HOURS=0
CHKROOTKIT_STATUS="${SW_STATUS_OK}"
declare -a WARNING_LIST=()
declare -a WARNING_OK_LIST=()

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

chkrootkit_collect() {

    if [[ ! -r "${CHKROOTKIT_LOG}" ]]; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "Cannot read ${CHKROOTKIT_LOG} (missing, or chkrootkit hasn't run yet)"

        return 1

    fi

    CHKROOTKIT_LOG_MTIME="$(stat -c %Y "${CHKROOTKIT_LOG}" 2>/dev/null)"
    CHKROOTKIT_LOG_AGE_HOURS=$(( ( $(date +%s) - CHKROOTKIT_LOG_MTIME ) / 3600 ))

    CHKROOTKIT_WARNINGS=0
    CHKROOTKIT_INFECTED=0

    local line

    while IFS= read -r line
    do

        # Anchored at end-of-line on purpose: the free-text detail lines
        # that follow a warning (e.g. "WARNING: The following suspicious
        # files...") don't themselves END with the bare word WARNING, so
        # they're never double-counted -- only the one status line per
        # check is.
        if [[ "${line}" =~ INFECTED$ ]]; then

            # Plain assignment, not '(( VAR++ ))' as a bare command: the
            # latter returns the PRE-increment value as its exit status,
            # which is 0 (false) on the very first match and would trip
            # errexit. Assignment is always exit-status 0.
            CHKROOTKIT_INFECTED=$(( CHKROOTKIT_INFECTED + 1 ))

        elif [[ "${line}" =~ WARNING$ ]]; then

            CHKROOTKIT_WARNINGS=$(( CHKROOTKIT_WARNINGS + 1 ))

        fi

    done < "${CHKROOTKIT_LOG}"

}

chkrootkit_analyze() {

    CHKROOTKIT_STATUS="${SW_STATUS_OK}"

    WARNING_LIST=()
    CHKROOTKIT_FALSE_POSITIVES=0
    WARNING_OK_LIST=()
    
    local chkrootkit_eval=""
    local warning_type=""
    local warning_status=""


    # -------------------------------------------------------------------------
    # Evaluate warnings validated by chkrootkit_eval.sh
    # -------------------------------------------------------------------------

    if sw_cache_exists "chkrootkit.status"; then

        while IFS= read -r line
        do

            # Expected format:
            #
            # WARNING: Suspicious files: OK
            # WARNING: sniffers: OK
            #
            if [[ "${line}" =~ ^WARNING:\ (.*):\ (OK|WARNING|UNKNOWN)$ ]]; then

                warning_type="${BASH_REMATCH[1]}"
                warning_status="${BASH_REMATCH[2]}"

                case "${warning_status}" in

                    OK)

                        CHKROOTKIT_FALSE_POSITIVES=$(( CHKROOTKIT_FALSE_POSITIVES + 1 ))
                        if (( CHKROOTKIT_WARNINGS > 0 )); then
                            CHKROOTKIT_WARNINGS=$(( CHKROOTKIT_WARNINGS - 1 ))
                        fi

                        WARNING_OK_LIST+=( "${warning_type}" )

                        ;;

                    WARNING|UNKNOWN)

                        WARNING_LIST+=( "${warning_type}" )

                        ;;

                esac

            fi

        done < <(sw_cache_read "chkrootkit.status")

    fi


    # -------------------------------------------------------------------------
    # Any warnings that remain after the evaluator are real/unresolved.
    # -------------------------------------------------------------------------

    if (( CHKROOTKIT_WARNINGS > 0 )); then

        # If the evaluator didn't identify the remaining warnings individually,
        # keep the generic warning count for the overall status.
        :
        
    fi


    # -------------------------------------------------------------------------
    # Determine status
    # -------------------------------------------------------------------------

    if (( CHKROOTKIT_INFECTED > 0 )); then

        CHKROOTKIT_STATUS="${SW_STATUS_CRITICAL}"

    elif (( CHKROOTKIT_WARNINGS > 0 )); then

        CHKROOTKIT_STATUS="${SW_STATUS_WARNING}"

    fi


    # A stale log (chkrootkit's own cron seems to have stopped running)
    # is worth flagging, but shouldn't downgrade a worse status already
    # found.
    if (( CHKROOTKIT_LOG_AGE_HOURS > CHKROOTKIT_MAX_AGE_HOURS )) &&
       [[ "${CHKROOTKIT_STATUS}" == "${SW_STATUS_OK}" ]]
    then

        CHKROOTKIT_STATUS="${SW_STATUS_WARNING}"

    fi

}

chkrootkit_update_state() {

    local order=20

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.label" "Chkrootkit"
    case "${CHKROOTKIT_STATUS}" in
        OK)
            sw_state_set "module.icon" "lucide/shield-check"
            ;;
        WARNING)
            sw_state_set "module.icon" "lucide/shield-alert"
            ;;
        CRITICAL)
            sw_state_set "module.icon" "lucide/shield-x"
            ;;
        *)
            sw_state_set "module.icon" "lucide/shield"
            ;;
    esac

    sw_state_set "module.order" "$MODULE_ORDER"

    sw_state_set "infected" "${CHKROOTKIT_INFECTED}"
    sw_state_set "infected.label" "$(sw_translate "Infections")"
    sw_state_set "infected.order" "10"

    for key in "${!SW_STATE[@]}"; do
        if [[ "$key" =~ ^warning[0-9]+(\.(label|order))?$ ]]; then
            sw_state_delete_key "$key"
        fi
    done

    sw_state_set "warnings" "${CHKROOTKIT_WARNINGS}"
    sw_state_set "warnings.label" "$(sw_translate "Warnings")"
    sw_state_set "warnings.order" "20"

    for i in "${!WARNING_LIST[@]}"
    do
    echo "${WARNING_LIST[$i]}"
        order=$(( order + 10 ))
        sw_state_set "warning${i}" "${WARNING_LIST[$i]}"
        sw_state_set "warning${i}.label" "$(printf "$(sw_translate "Warning %s")\n" "$((i + 1))")"
        sw_state_set "warning${i}.order" "$order"
    done

    order=$(( order + 10 ))

    for key in "${!SW_STATE[@]}"; do
        if [[ "$key" =~ ^false[0-9]+(\.(label|order))?$ ]]; then
            sw_state_delete_key "$key"
        fi
    done

    sw_state_set "falses" "${CHKROOTKIT_FALSE_POSITIVES}"
    sw_state_set "falses.label" "$(sw_translate "False positives")"
    sw_state_set "falses.order" "$order"
    
    for i in "${!WARNING_OK_LIST[@]}"
    do
        order=$(( order + 10 ))
        sw_state_set "false${i}" "${WARNING_OK_LIST[$i]}"
        sw_state_set "false${i}.label" "$(printf "$(sw_translate "False %s")\n" "$((i + 1))")"
        sw_state_set "false${i}.order" "$order"
    done

    order=$(( order + 10 ))

    sw_state_set "last_scan" "$(date -d "@${CHKROOTKIT_LOG_MTIME}" '+%Y-%m-%d %H:%M' 2>/dev/null)"
    sw_state_set "last_scan.label" "$(sw_translate "Last run")"
    sw_state_set "last_scan.order" "$order"

    
}

chkrootkit_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Chkrootkit: ${CHKROOTKIT_INFECTED} infected, ${CHKROOTKIT_WARNINGS} warning(s), log age ${CHKROOTKIT_LOG_AGE_HOURS}h (${CHKROOTKIT_STATUS})"

}

sw_module_run() {

    sw_state_use "chkrootkit"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi
    
    sw_state_load

    chkrootkit_collect || return 1

    chkrootkit_analyze

    sw_status_update "${CHKROOTKIT_STATUS}" || return 1

    chkrootkit_update_state

    sw_state_save

    chkrootkit_report

}
