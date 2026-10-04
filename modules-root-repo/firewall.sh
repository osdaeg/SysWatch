#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# firewall module
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Firewall"
readonly MODULE_DESCRIPTION="Firewall status and configuration"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-1000}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

FIREWALL_PROVIDER=""
FIREWALL_STATUS="${SW_STATUS_UNKNOWN}"

# -----------------------------------------------------------------------------
# UFW
# -----------------------------------------------------------------------------

firewall_collect_ufw() {

    local output
    local status_line
    local version
    local rules
    local rules_ipv6
    local rules_ipv4

    output="$(ufw status verbose 2>/dev/null)" || {
        return 1
    }

    status_line="$(printf '%s\n' "${output}" |
        sed -n 's/^Status: //p' |
        head -n 1)"

    [[ -n "${status_line}" ]] || {
        return 1
    }

    FIREWALL_PROVIDER="UFW"

    version="$(ufw version 2>/dev/null |
        sed -n 's/^ufw \([0-9][^ ]*\).*$/\1/p' |
        head -n 1)"

    rules="$(
        ufw status numbered 2>/dev/null |
            grep -c '^\[[0-9]\+\]'
    )"

    rules_ipv6="$(
        ufw status numbered 2>/dev/null |
            grep -c '(v6)'
    )"

    rules_ipv4=$((rules - rules_ipv6))

    sw_state_set "provider" "UFW"
    sw_state_set "provider.label" "$(sw_translate "Provider")"
    sw_state_set "version" "${version}"
    sw_state_set "version.label" "$(sw_translate "Version")"

    sw_state_set "incoming" "$(
        sw_translate "$(
            printf '%s\n' "${output}" |
                sed -n 's/^Default: \([^,]*\) (incoming),.*/\1/p'
            )"
        )"
    sw_state_set "incoming.label" "$(sw_translate "Incoming")"

    sw_state_set "outgoing" "$(
        sw_translate "$(
            printf '%s\n' "${output}" |
                sed -n 's/^Default: [^,]* (incoming), \([^,]*\) (outgoing),.*/\1/p'
            )"
        )"
    sw_state_set "outgoing.label" "$(sw_translate "Outgoing")"

    sw_state_set "routed" "$(
        sw_translate "$(
            printf '%s\n' "${output}" |
                sed -n 's/^Default: [^,]* (incoming), [^,]* (outgoing), \([^,]*\) (routed).*/\1/p'
            )"
        )"
    sw_state_set "routed.label" "$(sw_translate "Routed")"

    sw_state_set "logging" "$(
        printf '%s\n' "${output}" |
            sed -n 's/^Logging: //p'
    )"
    sw_state_set "logging.label" "$(sw_translate "Logging")"

    sw_state_set "rules" "${rules}"
    sw_state_set "rules.label" "$(sw_translate "Rules")"
    sw_state_set "rules_ipv4" "${rules_ipv4}"
    sw_state_set "rules_ipv4.label" "$(sw_translate "IPv4 Rules")"
    sw_state_set "rules_ipv6" "${rules_ipv6}"
    sw_state_set "rules_ipv6.label" "$(sw_translate "IPv6 Rules")"

    case "${status_line}" in

    active)
        FIREWALL_STATUS="${SW_STATUS_OK}"
        ;;

    inactive)
        FIREWALL_STATUS="${SW_STATUS_CRITICAL}"
        ;;

    *)
        FIREWALL_STATUS="${SW_STATUS_UNKNOWN}"
        ;;

    esac

}

# -----------------------------------------------------------------------------
# firewalld
# -----------------------------------------------------------------------------

firewall_collect_firewalld() {

    local state
    local version
    local active_zones
    local active_zone
    local interfaces
    local services
    local ports
    local rich_rules

    state="$(firewall-cmd --state 2>/dev/null |
        tail -n 1)"

    case "${state}" in

    running)
        FIREWALL_STATUS="${SW_STATUS_OK}"
        ;;

    "not running" | "Not running")
        FIREWALL_STATUS="${SW_STATUS_CRITICAL}"
        ;;

    *)
        FIREWALL_STATUS="${SW_STATUS_UNKNOWN}"
        ;;

    esac

    FIREWALL_PROVIDER="firewalld"

    version="$(firewall-cmd --version 2>/dev/null)"

    active_zones="$(
        firewall-cmd --get-active-zones 2>/dev/null |
            awk '
            /^[^[:space:]]/ {
                print $1
            }
        ' |
            paste -sd ',' -
    )"

    active_zone="$(
        firewall-cmd --get-active-zones 2>/dev/null |
            awk '
            /^[^[:space:]]/ {
                print $1
                exit
            }
        '
    )"

    interfaces=""

    if [[ -n "${active_zone}" ]]; then

        interfaces="$(
            firewall-cmd \
                --zone="${active_zone}" \
                --list-interfaces 2>/dev/null |
                paste -sd ',' -
        )"

    fi

    services=""
    ports=""
    rich_rules=""

    if [[ -n "${active_zone}" ]]; then

        services="$(
            firewall-cmd \
                --zone="${active_zone}" \
                --list-services 2>/dev/null |
                paste -sd ',' -
        )"

        ports="$(
            firewall-cmd \
                --zone="${active_zone}" \
                --list-ports 2>/dev/null |
                paste -sd ',' -
        )"

        rich_rules="$(
            firewall-cmd \
                --zone="${active_zone}" \
                --list-rich-rules 2>/dev/null
        )"

    fi

    sw_state_set "provider" "firewalld"
    sw_state_set "provider.label" "$(sw_translate "Provider")"
    sw_state_set "version" "${version}"
    sw_state_set "version.label" "$(sw_translate "Version")"
    sw_state_set "zones" "${active_zones}"
    sw_state_set "zones.label" "$(sw_translate "Zones")"
    sw_state_set "zone" "${active_zone}"
    sw_state_set "zone.label" "$(sw_translate "Zone")"
    sw_state_set "interfaces" "${interfaces}"
    sw_state_set "interfaces.label" "$(sw_translate "Interfaces")"
    sw_state_set "services" "${services}"
    sw_state_set "services.label" "$(sw_translate "Services")"
    sw_state_set "ports" "${ports}"
    sw_state_set "ports.label" "$(sw_translate "Ports")"

    sw_state_set "rich_rules" "$(
        printf '%s\n' "${rich_rules}" |
            sed '/^[[:space:]]*$/d' |
            wc -l
    )"

    sw_state_set "forward" "$(
        firewall-cmd \
            --zone="${active_zone}" \
            --query-forward 2>/dev/null
    )"

    sw_state_set "masquerade" "$(
        firewall-cmd \
            --zone="${active_zone}" \
            --query-masquerade 2>/dev/null
    )"

}

# -----------------------------------------------------------------------------
# nftables
# -----------------------------------------------------------------------------

firewall_collect_nftables() {

    local ruleset
    local tables
    local chains
    local rules
    local input_policy
    local forward_policy

    ruleset="$(nft list ruleset 2>/dev/null)" || {
        return 1
    }

    [[ -n "${ruleset}" ]] || {
        FIREWALL_PROVIDER="nftables"
        FIREWALL_STATUS="${SW_STATUS_UNKNOWN}"
        return 0
    }

    FIREWALL_PROVIDER="nftables"

    tables="$(
        printf '%s\n' "${ruleset}" |
            grep -c '^table '
    )"

    chains="$(
        printf '%s\n' "${ruleset}" |
            grep -c '^[[:space:]]*chain '
    )"

    input_policy="$(
        printf '%s\n' "${ruleset}" |
            sed -n '
            /chain input[[:space:]]*{/{
                :a
                n
                /policy /{
                    s/.*policy \([^;]*\);.*/\1/p
                    q
                }
                ba
            }
        '
    )"

    forward_policy="$(
        printf '%s\n' "${ruleset}" |
            sed -n '
            /chain forward[[:space:]]*{/{
                :a
                n
                /policy /{
                    s/.*policy \([^;]*\);.*/\1/p
                    q
                }
                ba
            }
        '
    )"

    rules="$(
        printf '%s\n' "${ruleset}" |
            awk '
            /^[[:space:]]*chain / {
                in_chain=1
                next
            }

            in_chain && /^[[:space:]]*type / {
                next
            }

            in_chain && /^[[:space:]]*policy / {
                next
            }

            in_chain && /^[[:space:]]*}/ {
                in_chain=0
                next
            }

            in_chain && /^[[:space:]]+/ {
                count++
            }

            END {
                print count + 0
            }
        '
    )"

    sw_state_set "provider" "nftables"
    sw_state_set "provider.label" "$(sw_translate "Provider")"
    sw_state_set "tables" "${tables}"
    sw_state_set "tables.label" "$(sw_translate "Tables")"
    sw_state_set "chains" "${chains}"
    sw_state_set "chains.label" "$(sw_translate "Chains")"
    sw_state_set "rules" "${rules}"
    sw_state_set "rules.label" "$(sw_translate "Rules")"
    sw_state_set "input_policy" "${input_policy}"
    sw_state_set "unput_policy.label" "$(sw_translate "Input policy")"
    sw_state_set "forward_policy" "${forward_policy}"
    sw_state_set "forward_policy.label" "$(sw_translate "Forward policy")"

    if ((chains > 0)); then

        FIREWALL_STATUS="${SW_STATUS_OK}"

    else

        FIREWALL_STATUS="${SW_STATUS_UNKNOWN}"

    fi

}

# -----------------------------------------------------------------------------
# Provider detection
# -----------------------------------------------------------------------------

firewall_collect() {

    FIREWALL_PROVIDER=""
    FIREWALL_STATUS="${SW_STATUS_UNKNOWN}"

    if command -v ufw >/dev/null 2>&1; then

        firewall_collect_ufw
        return $?

    fi

    if command -v firewall-cmd >/dev/null 2>&1; then

        firewall_collect_firewalld
        return $?

    fi

    if command -v nft >/dev/null 2>&1; then

        firewall_collect_nftables
        return $?

    fi

    FIREWALL_STATUS="${SW_STATUS_UNKNOWN}"

}

# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------

firewall_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "Firewall"
    sw_state_set "module.icon" "lucide/shield"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Common data
    # -------------------------------------------------------------------------

    sw_state_set "provider" "${FIREWALL_PROVIDER}"
    sw_state_set "provider.label" "$(sw_translate "Provider")"
    sw_state_set "status" "${FIREWALL_STATUS}"
    sw_state_set "status.label" "$(sw_translate "Status")"

}

# -----------------------------------------------------------------------------
# Report
# -----------------------------------------------------------------------------

firewall_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "Provider: ${FIREWALL_PROVIDER:-unknown} (${FIREWALL_STATUS})"

}

# -----------------------------------------------------------------------------
# Module entry point
# -----------------------------------------------------------------------------

sw_module_run() {

    sw_state_use "firewall"
    sw_state_load

    firewall_collect

    sw_status_update "${FIREWALL_STATUS}" || return 1

    firewall_update_state

    sw_state_save

    firewall_report

}
