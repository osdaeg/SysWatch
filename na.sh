#!/usr/bin/env bash

#
# SysWatch - network.sh
# Controlled test: P0.3
#

MODULE_NAME="Network"
SW_STATUS_OK="OK"
SW_STATUS_WARNING="WARNING"
SW_STATUS_CRITICAL="CRITICAL"
SW_STATUS_UNKNOWN="UNKNOWN"

NETWORK_INTERFACES=("enp1s0")
NETWORK_DEVICE_COUNT=1

GLOBAL_STATUS="OK"
GLOBAL_STATE_SAVED=""
STATE_CONTEXT=""
STATE_DELETED=""
STATE_SAVE_COUNT=0
STATE_LOAD_COUNT=0

READ_CALLED=0
DETECT_CALLED=0

OLD_INTERFACE_STATE="status=OK"

TOTAL=0
PASSED=0
FAILED=0

#
# Simulated ip command
#

ip() {

    case "$IP_MODE" in

    normal)
        printf '%s\n' \
            "1: lo: <LOOPBACK,UP> mtu 65536" \
            "2: enp1s0: <BROADCAST,UP> mtu 1500" \
            "3: wlx503eaa33ebe0: <BROADCAST,UP> mtu 1500"
        return 0
        ;;

    empty)
        printf '%s\n' \
            "1: lo: <LOOPBACK,UP> mtu 65536"
        return 0
        ;;

    failure)
        echo "Simulated ip failure" >&2
        return 1
        ;;

    esac

}

#
# Simulated SysWatch helpers
#

sw_require_command() {
    return 0
}

sw_log_error() {
    printf 'LOG ERROR: %s\n' "$2"
}

sw_log_warning() {
    printf 'LOG WARNING: %s\n' "$2"
}

sw_state_use() {
    STATE_CONTEXT="$1"
}

sw_state_load() {
    STATE_LOAD_COUNT=$((STATE_LOAD_COUNT + 1))
}

sw_status_update() {
    GLOBAL_STATUS="$1"
}

sw_state_save() {
    STATE_SAVE_COUNT=$((STATE_SAVE_COUNT + 1))
    GLOBAL_STATE_SAVED="$GLOBAL_STATUS"
}

sw_state_delete() {
    STATE_DELETED="$STATE_CONTEXT"
}

#
# Simulated collection functions
#

network_read_interfaces() {
    READ_CALLED=1
}

network_detect_active_interface() {
    DETECT_CALLED=1
}

#
# Functions under test
#

network_discover_interfaces() {

    local output

    output=$(ip -o link show) || return 1

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

network_collect() {

    sw_require_command ip || return 127

    if ! network_discover_interfaces; then

        sw_log_error \
            "Network" \
            "Failed to discover network interfaces (ip -o link show)"

        sw_state_use "$MODULE_NAME"
        sw_state_load

        sw_status_update "${SW_STATUS_UNKNOWN}" || return 1
        sw_state_save

        return 1

    fi

    if ((NETWORK_DEVICE_COUNT == 0)); then

        sw_log_warning \
            "Network" \
            "No recognized network interfaces detected"

        sw_state_use "$MODULE_NAME"
        sw_state_load

        sw_status_update "${SW_STATUS_UNKNOWN}" || return 1
        sw_state_save

        return 1

    fi

    sw_state_use "$MODULE_NAME"
    sw_state_delete

    network_read_interfaces
    network_detect_active_interface

}

#
# Test helpers
#

reset_test() {

    NETWORK_INTERFACES=("enp1s0")
    NETWORK_DEVICE_COUNT=1

    GLOBAL_STATUS="OK"
    GLOBAL_STATE_SAVED=""
    STATE_CONTEXT=""
    STATE_DELETED=""
    STATE_SAVE_COUNT=0
    STATE_LOAD_COUNT=0

    READ_CALLED=0
    DETECT_CALLED=0

    OLD_INTERFACE_STATE="status=OK"

}

check() {

    local description="$1"
    local condition="$2"

    TOTAL=$((TOTAL + 1))

    if [[ "$condition" == "true" ]]; then

        printf 'PASS: %s\n' "$description"
        PASSED=$((PASSED + 1))

    else

        printf 'FAIL: %s\n' "$description"
        FAILED=$((FAILED + 1))

    fi

}

#
# TEST 1 - Normal discovery
#

echo
echo "=== Test 1: Normal discovery ==="

reset_test
IP_MODE="normal"

network_collect
RC=$?

check "Collection succeeds" "$([[ $RC -eq 0 ]] && echo true || echo false)"

check "Two interfaces discovered" \
    "$([[ $NETWORK_DEVICE_COUNT -eq 2 ]] && echo true || echo false)"

check "Ethernet detected" \
    "$([[ "${NETWORK_INTERFACES[0]}" == "enp1s0" ]] && echo true || echo false)"

check "Wi-Fi detected" \
    "$([[ "${NETWORK_INTERFACES[1]}" == "wlx503eaa33ebe0" ]] && echo true || echo false)"

check "Global state deleted" \
    "$([[ "$STATE_DELETED" == "$MODULE_NAME" ]] && echo true || echo false)"

check "Normal collection continues" \
    "$([[ $READ_CALLED -eq 1 && $DETECT_CALLED -eq 1 ]] && echo true || echo false)"

check "No UNKNOWN state saved" \
    "$([[ $STATE_SAVE_COUNT -eq 0 ]] && echo true || echo false)"

#
# TEST 2 - No recognized interfaces
#

echo
echo "=== Test 2: Zero recognized interfaces ==="

reset_test
IP_MODE="empty"

network_collect
RC=$?

check "Collection returns error" \
    "$([[ $RC -ne 0 ]] && echo true || echo false)"

check "Interface count is zero" \
    "$([[ $NETWORK_DEVICE_COUNT -eq 0 ]] && echo true || echo false)"

check "Global status becomes UNKNOWN" \
    "$([[ "$GLOBAL_STATUS" == "UNKNOWN" ]] && echo true || echo false)"

check "UNKNOWN state is saved" \
    "$([[ "$GLOBAL_STATE_SAVED" == "UNKNOWN" && $STATE_SAVE_COUNT -eq 1 ]] && echo true || echo false)"

check "Global state context used" \
    "$([[ "$STATE_CONTEXT" == "$MODULE_NAME" ]] && echo true || echo false)"

check "Previous global state loaded" \
    "$([[ $STATE_LOAD_COUNT -eq 1 ]] && echo true || echo false)"

check "Previous interface state preserved" \
    "$([[ "$OLD_INTERFACE_STATE" == "status=OK" ]] && echo true || echo false)"

check "Previous global state not deleted" \
    "$([[ -z "$STATE_DELETED" ]] && echo true || echo false)"

check "Normal collection does not continue" \
    "$([[ $READ_CALLED -eq 0 && $DETECT_CALLED -eq 0 ]] && echo true || echo false)"

#
# TEST 3 - ip command failure
#

echo
echo "=== Test 3: ip command failure ==="

reset_test
IP_MODE="failure"

network_collect
RC=$?

check "Collection returns error" \
    "$([[ $RC -ne 0 ]] && echo true || echo false)"

check "Global status becomes UNKNOWN" \
    "$([[ "$GLOBAL_STATUS" == "UNKNOWN" ]] && echo true || echo false)"

check "UNKNOWN state is saved" \
    "$([[ "$GLOBAL_STATE_SAVED" == "UNKNOWN" && $STATE_SAVE_COUNT -eq 1 ]] && echo true || echo false)"

check "Previous interface list preserved" \
    "$([[ "${NETWORK_INTERFACES[0]}" == "enp1s0" ]] && echo true || echo false)"

check "Previous interface state preserved" \
    "$([[ "$OLD_INTERFACE_STATE" == "status=OK" ]] && echo true || echo false)"

check "Previous global state not deleted" \
    "$([[ -z "$STATE_DELETED" ]] && echo true || echo false)"

check "Normal collection does not continue" \
    "$([[ $READ_CALLED -eq 0 && $DETECT_CALLED -eq 0 ]] && echo true || echo false)"

#
# Summary
#

echo
echo "=================================="
echo "Total:  $TOTAL"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "=================================="

((FAILED == 0))
