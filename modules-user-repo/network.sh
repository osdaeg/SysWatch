#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# CPU monitoring module
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Network"
readonly MODULE_SCRIPT="$(realpath "${BASH_SOURCE[0]}")"
readonly MODULE_DESCRIPTION="Network state monitoring"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-120}
MODULE_INTERVAL_NORMAL=${MODULE_INTERVAL_NORMAL:-}
MODULE_INTERVAL_ALT=${MODULE_INTERVAL_ALT:-}
MODULE_ORDER=${MODULE_ORDER:-30}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly NETWORK_WARNING_RX="${NETWORK_WARNING_RX:-100}"
readonly NETWORK_CRITICAL_RX="${NETWORK_CRITICAL_RX:-500}"

readonly NETWORK_WARNING_TX="${NETWORK_WARNING_TX:-100}"
readonly NETWORK_CRITICAL_TX="${NETWORK_CRITICAL_TX:-500}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

NETWORK_INTERFACES=()

NETWORK_NAME=()
NETWORK_TYPE=()

NETWORK_IP=()
NETWORK_MAC=()

NETWORK_STATE=()
NETWORK_CARRIER=()

NETWORK_SPEED=()
NETWORK_DUPLEX=()

NETWORK_RX_BYTES=()
NETWORK_TX_BYTES=()

NETWORK_RX_RATE=()
NETWORK_TX_RATE=()

NETWORK_RX_PACKETS=()
NETWORK_TX_PACKETS=()

NETWORK_RX_ERRORS=()
NETWORK_TX_ERRORS=()

NETWORK_MTU=()

NETWORK_DEVICE_COUNT=0

NETWORK_STATUS=()

NETWORK_SSID=()
NETWORK_SIGNAL=()
NETWORK_FREQUENCY=()
NETWORK_BITRATE=()

NETWORK_LABEL=()

NETWORK_ACTIVE_INTERFACE=""

NETWORK_PREV_RX_ERRORS=()
NETWORK_PREV_TX_ERRORS=()

NETWORK_IPV6=()
NETWORK_IPV6_LINK_LOCAL=()

NETWORK_GATEWAY=()
NETWORK_GATEWAY_IPV6=()

NETWORK_ROUTES=()

NETWORK_DNS=()
NETWORK_DNS_IPV6=()

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

network_routes() {

    local iface="$1"

    ip -4 route show dev "${iface}" |
        awk '$1 != "default" { print $1 }' |
        paste -sd ","
}

network_read_gateways() {

    local i
    local iface
    local gateway

    NETWORK_GATEWAY=()
    NETWORK_GATEWAY_IPV6=()

    #
    # Initialize arrays, preserving interface indexes.
    #

    for ((i = 0; i < NETWORK_DEVICE_COUNT; i++)); do
        NETWORK_GATEWAY+=("")
        NETWORK_GATEWAY_IPV6+=("")
    done

    #
    # IPv4 default gateways.
    #

    while IFS=$'\t' read -r iface gateway; do

        [[ -z "$iface" || -z "$gateway" ]] && continue

        for ((i = 0; i < NETWORK_DEVICE_COUNT; i++)); do

            if [[ "${NETWORK_INTERFACES[$i]}" == "$iface" ]]; then

                if [[ -n "${NETWORK_GATEWAY[$i]}" ]]; then
                    NETWORK_GATEWAY[$i]+=", "
                fi

                NETWORK_GATEWAY[$i]+="$gateway"

                break

            fi

        done

    done < <(

        ip -4 route show default |
            awk '
                {
                    iface = ""
                    gateway = ""

                    for (i = 1; i <= NF; i++) {

                        if ($i == "dev") {
                            iface = $(i + 1)
                        }

                        if ($i == "via") {
                            gateway = $(i + 1)
                        }

                    }

                    if (iface != "" && gateway != "") {
                        print iface "\t" gateway
                    }
                }
            '

    )

    #
    # IPv6 default gateways.
    #

    while IFS=$'\t' read -r iface gateway; do

        [[ -z "$iface" || -z "$gateway" ]] && continue

        for ((i = 0; i < NETWORK_DEVICE_COUNT; i++)); do

            if [[ "${NETWORK_INTERFACES[$i]}" == "$iface" ]]; then

                if [[ -n "${NETWORK_GATEWAY_IPV6[$i]}" ]]; then
                    NETWORK_GATEWAY_IPV6[$i]+=", "
                fi

                NETWORK_GATEWAY_IPV6[$i]+="$gateway"

                break

            fi

        done

    done < <(

        ip -6 route show default |
            awk '
                {
                    iface = ""
                    gateway = ""

                    for (i = 1; i <= NF; i++) {

                        if ($i == "dev") {
                            iface = $(i + 1)
                        }

                        if ($i == "via") {
                            gateway = $(i + 1)
                        }

                    }

                    if (iface != "" && gateway != "") {
                        print iface "\t" gateway
                    }
                }
            '

    )

}

network_read_previous_errors() {

    local i

    NETWORK_PREV_RX_ERRORS=()
    NETWORK_PREV_TX_ERRORS=()

    for ((i = 0; i < NETWORK_DEVICE_COUNT; i++)); do

        sw_state_use "${NETWORK_INTERFACES[$i]}"
        sw_state_load

        NETWORK_PREV_RX_ERRORS+=("$(sw_state_get "rx_errors")")
        NETWORK_PREV_TX_ERRORS+=("$(sw_state_get "tx_errors")")

    done

}

network_sysfs() {

    local iface="$1"
    local file="$2"

    cat "/sys/class/net/${iface}/${file}" 2>/dev/null

}

network_stat() {

    local iface="$1"
    local stat="$2"

    cat "/sys/class/net/${iface}/statistics/${stat}" 2>/dev/null

}

network_ipv4() {

    local iface="$1"

    ip -4 -o addr show dev "${iface}" |
        awk '{print $4}' |
        cut -d/ -f1

}

network_read_dns() {

    local iface
    local dns
    local dns_ipv6
    local resolv_dns=""
    local resolv_dns_ipv6=""

    #
    # Initialize arrays.
    #

    NETWORK_DNS=()
    NETWORK_DNS_IPV6=()

    #
    # nmcli available: read DNS per interface.
    #

    if command -v nmcli >/dev/null 2>&1; then

        for iface in "${NETWORK_INTERFACES[@]}"; do

            dns="$(
                nmcli -g IP4.DNS device show "${iface}" 2>/dev/null |
                    awk 'NF { if (dns != "") dns = dns ", "; dns = dns $0 } END { print dns }'
            )"

            dns_ipv6="$(
                nmcli -g IP6.DNS device show "${iface}" 2>/dev/null |
                    awk 'NF { if (dns != "") dns = dns ", "; dns = dns $0 } END { print dns }'
            )"

            NETWORK_DNS+=("${dns}")
            NETWORK_DNS_IPV6+=("${dns_ipv6}")

        done

        return 0

    fi

    #
    # Fallback: /etc/resolv.conf.
    #

    if [[ -r /etc/resolv.conf ]]; then

        resolv_dns="$(
            awk '
                $1 == "nameserver" && $2 !~ /:/ {
                    if (dns != "") dns = dns ", "
                    dns = dns $2
                }
                END { print dns }
            ' /etc/resolv.conf
        )"

        resolv_dns_ipv6="$(
            awk '
                $1 == "nameserver" && $2 ~ /:/ {
                    if (dns != "") dns = dns ", "
                    dns = dns $2
                }
                END { print dns }
            ' /etc/resolv.conf
        )"

    fi

    #
    # Assign global DNS only to active interface.
    #

    for iface in "${NETWORK_INTERFACES[@]}"; do

        if [[ "${iface}" == "${NETWORK_ACTIVE_INTERFACE}" ]]; then
            NETWORK_DNS+=("${resolv_dns}")
            NETWORK_DNS_IPV6+=("${resolv_dns_ipv6}")
        else
            NETWORK_DNS+=("")
            NETWORK_DNS_IPV6+=("")
        fi

    done

}

network_detect_active_interface() {

    NETWORK_ACTIVE_INTERFACE=""

    NETWORK_ACTIVE_INTERFACE="$(
        ip route get 1.1.1.1 2>/dev/null |
            awk '
                {
                    for (i = 1; i <= NF; i++) {
                        if ($i == "dev") {
                            print $(i + 1)
                            exit
                        }
                    }
                }
            '
    )"

}

network_discover_interfaces() {

    local output

    #
    # Capture command output and verify its exit status.
    #

    output=$(ip -o link show) || return 1

    #
    # Filter recognized interfaces.
    #

    mapfile -t NETWORK_INTERFACES < <(

        printf '%s\n' "$output" |
            awk -F': ' '

            {
                sub(/@.*/, "", $2)
            }

            $2 ~ /^(en|eth|wl|wlan)/ {

                print $2

            }

        '

    )

    NETWORK_DEVICE_COUNT="${#NETWORK_INTERFACES[@]}"

    return 0

}

network_read_interfaces() {

    local iface

    NETWORK_LABEL=()

    NETWORK_TYPE=()

    NETWORK_IP=()
    NETWORK_MAC=()

    NETWORK_STATE=()
    NETWORK_CARRIER=()

    NETWORK_SPEED=()
    NETWORK_DUPLEX=()

    NETWORK_RX_BYTES=()
    NETWORK_TX_BYTES=()

    NETWORK_RX_PACKETS=()
    NETWORK_TX_PACKETS=()

    NETWORK_RX_ERRORS=()
    NETWORK_TX_ERRORS=()

    NETWORK_MTU=()

    NETWORK_IPV6=()
    NETWORK_IPV6_LINK_LOCAL=()

    NETWORK_ROUTES=()

    for iface in "${NETWORK_INTERFACES[@]}"; do

        #
        # Identification
        #

        NETWORK_LABEL+=("${iface}")

        NETWORK_TYPE+=("$(
            cat "/sys/class/net/${iface}/type"
        )")

        NETWORK_MAC+=("$(
            cat "/sys/class/net/${iface}/address"
        )")

        NETWORK_IP+=("$(
            ip -4 -o addr show dev "${iface}" |
                awk '{print $4}' |
                cut -d/ -f1
        )")

        NETWORK_IPV6+=("$(
            ip -6 -o addr show dev "${iface}" scope global |
                awk '{print $4}' |
                cut -d/ -f1 |
                paste -sd ', ' -
        )")

        NETWORK_IPV6_LINK_LOCAL+=("$(
            ip -6 -o addr show dev "${iface}" scope link |
                awk '{print $4}' |
                cut -d/ -f1 |
                paste -sd ', ' -
        )")

        #
        # Link
        #

        NETWORK_STATE+=("$(
            cat "/sys/class/net/${iface}/operstate"
        )")

        NETWORK_CARRIER+=("$(
            cat "/sys/class/net/${iface}/carrier" 2>/dev/null
        )")

        NETWORK_SPEED+=("$(
            cat "/sys/class/net/${iface}/speed" 2>/dev/null
        )")

        NETWORK_DUPLEX+=("$(
            cat "/sys/class/net/${iface}/duplex" 2>/dev/null
        )")

        NETWORK_MTU+=("$(
            cat "/sys/class/net/${iface}/mtu"
        )")

        #
        # Statistics
        #

        NETWORK_RX_BYTES+=("$(
            cat "/sys/class/net/${iface}/statistics/rx_bytes"
        )")

        NETWORK_TX_BYTES+=("$(
            cat "/sys/class/net/${iface}/statistics/tx_bytes"
        )")

        NETWORK_RX_PACKETS+=("$(
            cat "/sys/class/net/${iface}/statistics/rx_packets"
        )")

        NETWORK_TX_PACKETS+=("$(
            cat "/sys/class/net/${iface}/statistics/tx_packets"
        )")

        NETWORK_RX_ERRORS+=("$(
            cat "/sys/class/net/${iface}/statistics/rx_errors"
        )")

        NETWORK_TX_ERRORS+=("$(
            cat "/sys/class/net/${iface}/statistics/tx_errors"
        )")

        NETWORK_ROUTES+=("$(network_routes "${iface}")")

    done

}

network_calculate_rate() {

    # -----------------------------------------------------------------------
    # Computes the rate for a single interface index, reading _internal.prev_*
    # from whatever state is currently loaded (via sw_state_get).
    #
    # This function does NOT call sw_state_use/load/save itself: the caller
    # (network_update_state) owns the single load/save cycle per interface,
    # so state is only touched once per interface, per execution.
    # -----------------------------------------------------------------------

    local i="$1"
    local now="$2"

    local prev_rx
    local prev_tx
    local prev_time
    local elapsed

    prev_rx="$(sw_state_get _internal.prev_rx)"
    prev_tx="$(sw_state_get _internal.prev_tx)"
    prev_time="$(sw_state_get _internal.prev_time)"

    if [[ -n "$prev_time" ]]; then

        elapsed=$((now - prev_time))

        ((elapsed < 1)) && elapsed=1

        # The interface's byte counters live in the kernel and reset to 0
        # on every reboot, but _internal.prev_* is whatever was persisted
        # to disk before that reboot (much larger). If the current reading
        # is lower than what we saved last time, the counter rolled back
        # (reboot, or the interface was reset) -- there's no valid rate to
        # compute from this pair of samples, so report 0 instead of a
        # nonsense negative number.
        if ((NETWORK_RX_BYTES[$i] < prev_rx || NETWORK_TX_BYTES[$i] < prev_tx)); then

            NETWORK_RX_RATE[$i]=0
            NETWORK_TX_RATE[$i]=0

        else

            NETWORK_RX_RATE[$i]=$(((NETWORK_RX_BYTES[$i] - prev_rx) / elapsed))
            NETWORK_TX_RATE[$i]=$(((NETWORK_TX_BYTES[$i] - prev_tx) / elapsed))

        fi

    else

        NETWORK_RX_RATE[$i]=0
        NETWORK_TX_RATE[$i]=0

    fi

}

network_collect() {

    sw_require_command ip || return 127

    #
    # Discover interfaces.
    #

    if ! network_discover_interfaces; then

        sw_log_error \
            "Network" \
            "Failed to discover network interfaces (ip -o link show)"

        sw_state_use "$MODULE_NAME"
        sw_state_load

        sw_state_set "module_version" "${MODULE_VERSION}"

        sw_state_set "module.label" "$(sw_translate "Network")"

        sw_state_set "module.icon" "lucide/wifi-off"
        sw_state_set "module.order" "$MODULE_ORDER"

        sw_state_set "info" "$(sw_translate "Failed to discover network interfaces (ip -o link show)")"
        sw_state_set "info.label" "$(sw_translate "Information:")"

        sw_status_update "${SW_STATUS_UNKNOWN}" || return 1
        sw_state_save

        return 1

    fi

    #
    # No recognized interfaces.
    #

    if ((NETWORK_DEVICE_COUNT == 0)); then

        sw_log_warning \
            "Network" \
            "No recognized network interfaces detected"

        sw_state_use "$MODULE_NAME"
        sw_state_load

        sw_state_set "module_version" "${MODULE_VERSION}"

        sw_state_set "module.label" "$(sw_translate "Network")"

        sw_state_set "module.icon" "lucide/wifi-off"
        sw_state_set "module.order" "$MODULE_ORDER"

        sw_state_set "info" "$(sw_translate "No recognized network interfaces detected")"
        sw_state_set "info.label" "$(sw_translate "Information:")"

        sw_status_update "${SW_STATUS_UNKNOWN}" || return 1
        sw_state_save

        return 1

    fi

    #
    # Interfaces detected: remove previous global state.
    #

    sw_state_use "$MODULE_NAME"
    sw_state_delete

    #
    # Continue normal collection.
    #

    network_read_interfaces

    network_detect_active_interface

    network_read_previous_errors

    network_read_gateways

    network_read_dns

}

network_analyze() {

    NETWORK_GLOBAL_STATUS="${SW_STATUS_OK}"

    local i

    for ((i = 0; i < NETWORK_DEVICE_COUNT; i++)); do

        NETWORK_STATUS[$i]="${SW_STATUS_OK}"

        #
        # Link down
        #

        if [[ "${NETWORK_STATE[$i]}" != "up" ]]; then

            if [[ -n "${NETWORK_ACTIVE_INTERFACE}" ]] &&
                [[ "${NETWORK_INTERFACES[$i]}" != "${NETWORK_ACTIVE_INTERFACE}" ]]; then

                NETWORK_STATUS[$i]="NONE"

            else

                NETWORK_STATUS[$i]="${SW_STATUS_CRITICAL}"

            fi

        fi

        #
        # Carrier
        #

        if [[ -n "${NETWORK_CARRIER[$i]}" ]] &&
            [[ "${NETWORK_CARRIER[$i]}" == "0" ]]; then

            if [[ -n "${NETWORK_ACTIVE_INTERFACE}" ]] &&
                [[ "${NETWORK_INTERFACES[$i]}" != "${NETWORK_ACTIVE_INTERFACE}" ]]; then

                NETWORK_STATUS[$i]="NONE"

            else

                NETWORK_STATUS[$i]="${SW_STATUS_CRITICAL}"

            fi

        fi

        #
        # Link speed
        # P0.2: evaluate only valid positive integer values.
        #

        if [[ "${NETWORK_SPEED[$i]}" =~ ^[0-9]+$ ]] &&
            ((10#${NETWORK_SPEED[$i]} > 0)); then

            if ((10#${NETWORK_SPEED[$i]} < 100)) &&
                [[ "${NETWORK_STATUS[$i]}" == "${SW_STATUS_OK}" ]]; then

                NETWORK_STATUS[$i]="${SW_STATUS_WARNING}"

            fi
        fi

        #
        # RX errors
        # P0.4: detect new errors, ignoring historical counters.
        #

        if [[ "${NETWORK_PREV_RX_ERRORS[$i]}" =~ ^[0-9]+$ ]] &&
            [[ "${NETWORK_RX_ERRORS[$i]}" =~ ^[0-9]+$ ]]; then

            if ((NETWORK_RX_ERRORS[$i] > NETWORK_PREV_RX_ERRORS[$i])); then

                if [[ "${NETWORK_STATUS[$i]}" == "${SW_STATUS_OK}" ]]; then
                    NETWORK_STATUS[$i]="${SW_STATUS_WARNING}"
                fi

            fi

        fi

        #
        # TX errors
        # P0.4: detect new errors, ignoring historical counters.
        #

        if [[ "${NETWORK_PREV_TX_ERRORS[$i]}" =~ ^[0-9]+$ ]] &&
            [[ "${NETWORK_TX_ERRORS[$i]}" =~ ^[0-9]+$ ]]; then

            if ((NETWORK_TX_ERRORS[$i] > NETWORK_PREV_TX_ERRORS[$i])); then

                if [[ "${NETWORK_STATUS[$i]}" == "${SW_STATUS_OK}" ]]; then
                    NETWORK_STATUS[$i]="${SW_STATUS_WARNING}"
                fi

            fi

        fi

        #
        # Update global status
        #

        case "${NETWORK_STATUS[$i]}" in

        "${SW_STATUS_CRITICAL}")

            NETWORK_GLOBAL_STATUS="${SW_STATUS_CRITICAL}"
            ;;

        "${SW_STATUS_WARNING}")

            [[ "${NETWORK_GLOBAL_STATUS}" == "${SW_STATUS_OK}" ]] &&
                NETWORK_GLOBAL_STATUS="${SW_STATUS_WARNING}"
            ;;

        esac

    done

}

network_update_state() {

    local i
    local now
    local peak_rx
    local peak_tx
    local icon

    local show

    now=$(date +%s)

    for ((i = 0; i < NETWORK_DEVICE_COUNT; i++)); do

        sw_state_use "${NETWORK_INTERFACES[$i]}"

        if [[ -n "$MODULE_REMOTE" ]]; then
            sw_state_remote "$MODULE_REMOTE"
        fi
        sw_state_load

        network_calculate_rate "$i" "$now"

        #
        # ---------------------------------------------------------------------
        # Module
        # ---------------------------------------------------------------------
        #

        sw_state_set "module_version" "${MODULE_VERSION}"

        sw_state_set "module.label" "$(sw_translate "${NETWORK_LABEL[$i]}")"

        case "${NETWORK_INTERFACES[$i]}" in
        en* | eth*)
            icon="lucide/ethernet-port"
            ;;
        wl* | wlan*)
            icon="lucide/wifi"
            ;;
        *)
            icon="lucide/network"
            ;;
        esac

        sw_state_set "module.icon" "$icon"
        sw_state_set "module.order" "$MODULE_ORDER"

        #
        # ---------------------------------------------------------------------
        # Identification
        # ---------------------------------------------------------------------
        #

        sw_state_set "interface" "${NETWORK_INTERFACES[$i]}"
        sw_state_set "interface.hidden" "true"

        sw_state_set "type" "${NETWORK_TYPE[$i]}"
        sw_state_set "type.hidden" "true"

        sw_state_set "mac" "${NETWORK_MAC[$i]}"
        sw_state_set "mac.hidden" "true"

        sw_state_set "ip" "${NETWORK_IP[$i]}"
        sw_state_set "ip.label" "$(sw_translate "IPv4")"

        sw_state_set "ipv6" "${NETWORK_IPV6[$i]}"
        sw_state_set "ipv6.label" "$(sw_translate "IPv6")"

        sw_state_set "ipv6_link_local" "${NETWORK_IPV6_LINK_LOCAL[$i]}"
        sw_state_set "ipv6_link_local.label" "$(sw_translate "IPv6 link-local")"

        #
        # ---------------------------------------------------------------------
        # Link
        # ---------------------------------------------------------------------
        #

        sw_state_set "state" "${NETWORK_STATE[$i]}"
        sw_state_set "state.hidden" "true"

        sw_state_set "carrier" "${NETWORK_CARRIER[$i]}"
        sw_state_set "carrier.hidden" "true"

        sw_state_set "duplex" "${NETWORK_DUPLEX[$i]}"
        sw_state_set "duplex.hidden" "true"

        sw_state_set "mtu" "${NETWORK_MTU[$i]}"
        sw_state_set "mtu.hidden" "true"

        sw_state_set "speed" "${NETWORK_SPEED[$i]}"
        sw_state_set "speed.label" "$(sw_translate "Link")"
        sw_state_set "speed.unit" "Mbps"

        #
        # ---------------------------------------------------------------------
        # Current traffic
        # ---------------------------------------------------------------------
        #

        sw_state_set "rx_rate" "${NETWORK_RX_RATE[$i]}"
        sw_state_set "rx_rate.label" "$(sw_translate "Download")"
        sw_state_set "rx_rate.widget" "line"
        sw_state_set "rx_rate.order" "20"
        sw_state_set "rx_rate.scale" "zero"

        sw_state_set "tx_rate" "${NETWORK_TX_RATE[$i]}"
        sw_state_set "tx_rate.label" "$(sw_translate "Upload")"
        sw_state_set "tx_rate.widget" "line"
        sw_state_set "tx_rate.order" "30"
        sw_state_set "tx_rate.scale" "zero"

        #
        # ---------------------------------------------------------------------
        # Totals
        # ---------------------------------------------------------------------
        #

        sw_state_set "rx_total" "${NETWORK_RX_BYTES[$i]}"
        sw_state_set "rx_total.label" "$(sw_translate "↓ Total")"
        sw_state_set "rx_total.render" "bytes"

        sw_state_set "tx_total" "${NETWORK_TX_BYTES[$i]}"
        sw_state_set "tx_total.label" "$(sw_translate "↑ Total")"
        sw_state_set "tx_total.render" "bytes"

        #
        # ---------------------------------------------------------------------
        # Hidden statistics
        # ---------------------------------------------------------------------
        #

        sw_state_set "rx_packets" "${NETWORK_RX_PACKETS[$i]}"
        sw_state_set "rx_packets.hidden" "true"

        sw_state_set "tx_packets" "${NETWORK_TX_PACKETS[$i]}"
        sw_state_set "tx_packets.hidden" "true"

        sw_state_set "rx_errors" "${NETWORK_RX_ERRORS[$i]}"
        sw_state_set "rx_errors.hidden" "true"

        sw_state_set "tx_errors" "${NETWORK_TX_ERRORS[$i]}"
        sw_state_set "tx_errors.hidden" "true"

        #
        # Gateways
        #

        if [[ -n "${NETWORK_GATEWAY[$i]}" ]]; then

            sw_state_set "gateway" "${NETWORK_GATEWAY[$i]}"
            sw_state_set "gateway.label" "$(sw_translate "Gateway")"

        else

            sw_state_delete_key "gateway"

        fi

        if [[ -n "${NETWORK_GATEWAY_IPV6[$i]}" ]]; then

            sw_state_set "gateway_ipv6" "${NETWORK_GATEWAY_IPV6[$i]}"
            sw_state_set "gateway_ipv6.label" "$(sw_translate "IPv6 Gateway")"

        else

            sw_state_delete_key "gateway_ipv6"

        fi

        sw_state_set "routes" "${NETWORK_ROUTES[$i]}"
        sw_state_set "routes.label" "$(sw_translate "Routes")"

        #
        # ---------------------------------------------------------------------
        # Status
        # ---------------------------------------------------------------------
        #

        sw_state_set "status" "${NETWORK_STATUS[$i]}"

        #
        # ---------------------------------------------------------------------
        # History (CSV files are separate from .state; safe to touch before
        # the single sw_state_save below)
        # ---------------------------------------------------------------------
        #

        sw_csv_append \
            "${NETWORK_INTERFACES[$i]}" \
            "rx_rate" \
            "${NETWORK_RX_RATE[$i]}"

        sw_csv_append \
            "${NETWORK_INTERFACES[$i]}" \
            "tx_rate" \
            "${NETWORK_TX_RATE[$i]}"

        #
        # ---------------------------------------------------------------------
        # Peaks (last 10 samples, from CSV history)
        # ---------------------------------------------------------------------
        #

        peak_rx=$(sw_csv_last_max "${NETWORK_INTERFACES[$i]}" rx_rate 10)
        peak_tx=$(sw_csv_last_max "${NETWORK_INTERFACES[$i]}" tx_rate 10)

        sw_state_set "peak_rx" "${peak_rx}"
        sw_state_set "peak_rx.label" "$(sw_translate "RX Peak")"
        sw_state_set "peak_rx.hidden" "true"

        sw_state_set "peak_tx" "${peak_tx}"
        sw_state_set "peak_tx.label" "$(sw_translate "TX Peak")"
        sw_state_set "peak_tx.hidden" "true"

        #
        # ---------------------------------------------------------------------
        # Bookkeeping for next execution's rate calculation
        # ---------------------------------------------------------------------
        #

        sw_state_set "_internal.prev_rx" "${NETWORK_RX_BYTES[$i]}"
        sw_state_set "_internal.prev_tx" "${NETWORK_TX_BYTES[$i]}"
        sw_state_set "_internal.prev_time" "${now}"

        if [[ -n "${NETWORK_DNS[$i]}" ]]; then
            sw_state_set "dns" "${NETWORK_DNS[$i]}"
            sw_state_set "dns.label" "$(sw_translate "DNS")"
        else
            sw_state_delete_key "dns"
        fi

        if [[ -n "${NETWORK_DNS_IPV6[$i]}" ]]; then
            sw_state_set "dns_ipv6" "${NETWORK_DNS_IPV6[$i]}"
            sw_state_set "dns_ipv6.label" "$(sw_translate "IPv6 DNS")"
        else
            sw_state_delete_key "dns_ipv6"
        fi

        show="$(sw_state_get "show")"

        [[ -z "$show" ]] && show=1

        if (( show == 4 )); then
            show=1
            sw_state_set "dns.hidden" "false"
            sw_state_set "dns_ipv6.hidden" "false"
            sw_state_set "routes.hidden" "false"
            sw_state_set "gateway.hidden" "false"
            sw_state_set "gateway_ipv6.hidden" "false"
            sw_state_set "speed.hidden" "false"

            #sw_state_set "status" "${SW_STATUS_INFO}"
        else    
            ((show++))
            sw_state_set "dns.hidden" "true"
            sw_state_set "dns_ipv6.hidden" "true"
            sw_state_set "routes.hidden" "true"
            sw_state_set "gateway.hidden" "true"
            sw_state_set "gateway_ipv6.hidden" "true"
            sw_state_set "speed.hidden" "true"
        fi    

        sw_state_set "show" "$show"
        sw_state_set "show.hidden" "true"

        sw_state_save

    done

}

network_report() {

    local summary=""
    local i

    for ((i = 0; i < NETWORK_DEVICE_COUNT; i++)); do

        [[ -n "${summary}" ]] && summary+=", "

        summary+="${NETWORK_INTERFACES[$i]}=${NETWORK_STATUS[$i]}"

    done

    sw_log_info \
        "${MODULE_NAME}" \
        "Network: ${NETWORK_DEVICE_COUNT} interface(s): ${summary}"

}

sw_module_run() {

    network_collect || return 1

    network_analyze

    sw_status_update "${NETWORK_GLOBAL_STATUS}" || return 1

    network_update_state

    network_report

}
