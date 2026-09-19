#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# certificate expiration module
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Certificates"
readonly MODULE_DESCRIPTION="TLS certificate expiration"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-86400}
MODULE_ORDER=${MODULE_ORDER:-1300}
MODULE_REMOTE=${MODULE_REMOTE:-""}


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly CERT_HOSTS="${CERT_HOSTS:-}"
readonly CERT_WARNING_DAYS="${CERT_WARNING_DAYS:-30}"
readonly CERT_CRITICAL_DAYS="${CERT_CRITICAL_DAYS:-7}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

CERT_STATUS="${SW_STATUS_DISABLED}"

CERT_COUNT=0
CERT_OK=0
CERT_WARNING=0
CERT_CRITICAL=0
CERT_UNKNOWN=0

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

cert_collect() {

    CERT_COUNT=0
    CERT_OK=0
    CERT_WARNING=0
    CERT_CRITICAL=0
    CERT_UNKNOWN=0

    if [[ -z "${CERT_HOSTS}" ]]; then

        return

    fi

    local host
    local port
    local cert_date
    local expiry_epoch
    local now_epoch
    local remaining_days

    local entry

    IFS=';' read -ra CERT_LIST <<< "${CERT_HOSTS}"

    for entry in "${CERT_LIST[@]}"; do

        [[ -z "${entry}" ]] && continue

        host="${entry%:*}"
        port="${entry##*:}"

        if [[ -z "${host}" || -z "${port}" ]]; then

            CERT_UNKNOWN=$((CERT_UNKNOWN + 1))
            continue

        fi

        CERT_COUNT=$((CERT_COUNT + 1))

        cert_date="$(
            timeout 10 \
                openssl s_client \
                    -connect "${host}:${port}" \
                    -servername "${host}" \
                    </dev/null 2>/dev/null |
                openssl x509 -noout -enddate 2>/dev/null
        )"

        if [[ "${cert_date}" != notAfter=* ]]; then

            CERT_UNKNOWN=$((CERT_UNKNOWN + 1))
            continue

        fi

        cert_date="${cert_date#notAfter=}"

        expiry_epoch="$(date -d "${cert_date}" +%s 2>/dev/null)" || {

            CERT_UNKNOWN=$((CERT_UNKNOWN + 1))
            continue

        }

        now_epoch="$(date +%s)"

        remaining_days=$(( (expiry_epoch - now_epoch) / 86400 ))


        if (( remaining_days < 0 )); then

            CERT_CRITICAL=$((CERT_CRITICAL + 1))

        elif (( remaining_days <= CERT_CRITICAL_DAYS )); then

            CERT_CRITICAL=$((CERT_CRITICAL + 1))

        elif (( remaining_days <= CERT_WARNING_DAYS )); then

            CERT_WARNING=$((CERT_WARNING + 1))

        else

            CERT_OK=$((CERT_OK + 1))

        fi

    done

}

cert_analyze() {

    CERT_STATUS="${SW_STATUS_OK}"

    if (( CERT_CRITICAL > 0 )); then

        CERT_STATUS="${SW_STATUS_CRITICAL}"

    elif (( CERT_WARNING > 0 )); then

        CERT_STATUS="${SW_STATUS_WARNING}"

    elif (( CERT_OK == 0 )); then

        CERT_STATUS="${SW_STATUS_DISABLED}"

    fi

}

cert_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "Certificates"
    sw_state_set "module.icon" "lucide/shield-check"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Summary
    # -------------------------------------------------------------------------

    sw_state_set "count" "${CERT_COUNT}"

    sw_state_set "count.label" "Certificates"
    sw_state_set "count.order" "10"

    sw_state_set "ok" "${CERT_OK}"
    sw_state_set "warning" "${CERT_WARNING}"
    sw_state_set "critical" "${CERT_CRITICAL}"
    sw_state_set "unknown" "${CERT_UNKNOWN}"

}

cert_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Certificates: ${CERT_COUNT} checked, ${CERT_OK} OK, ${CERT_WARNING} warning, ${CERT_CRITICAL} critical, ${CERT_UNKNOWN} unknown (${CERT_STATUS})"

}

sw_module_run() {

    sw_require_command openssl || return 1
    
    sw_state_use "cert"

    #sw_state_remote "HOGAR-PC-Linux"

    sw_state_load

    cert_collect

    cert_analyze

    sw_status_update "${CERT_STATUS}" || return 1

    cert_update_state

    sw_state_save

    cert_report

}