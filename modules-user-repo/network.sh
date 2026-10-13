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
readonly MODULE_DESCRIPTION="Network state monitoring"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-120}
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

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

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

    mapfile -t NETWORK_INTERFACES < <(

        ip -o link show |
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

    network_discover_interfaces

    network_read_interfaces

    network_detect_active_interface

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

                NETWORK_STATUS[$i]="${SW_STATUS_INFO}"

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

                NETWORK_STATUS[$i]="${SW_STATUS_INFO}"

            else

                NETWORK_STATUS[$i]="${SW_STATUS_CRITICAL}"

            fi

        fi

        #
        # Link speed
        #

        if [[ -n "${NETWORK_SPEED[$i]}" ]]; then

            if ((NETWORK_SPEED[$i] < 100)) &&
                [[ "${NETWORK_STATUS[$i]}" == "${SW_STATUS_OK}" ]]; then

                NETWORK_STATUS[$i]="${SW_STATUS_WARNING}"

            fi

        fi

        #
        # RX errors
        #

        if [[ -n "${NETWORK_RX_ERRORS[$i]}" ]] &&
            ((NETWORK_RX_ERRORS[$i] > 0)); then

            NETWORK_STATUS[$i]="${SW_STATUS_WARNING}"

        fi

        #
        # TX errors
        #

        if [[ -n "${NETWORK_TX_ERRORS[$i]}" ]] &&
            ((NETWORK_TX_ERRORS[$i] > 0)); then

            NETWORK_STATUS[$i]="${SW_STATUS_WARNING}"

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
        sw_state_set "module.icon" "lucide/network"
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
