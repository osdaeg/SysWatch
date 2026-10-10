#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# funciones de mensajeria entre módulos para todos los scripts de syswatch
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------


MESSAGE_FROM_MODULE=""

# -----------------------------------------------------------------------------
# Message helpers
# -----------------------------------------------------------------------------

sw_message_send() {

    local state=$1
    local sender="$MODULE_NAME"
    local value=$2
    local persist=$3
    local id=$4
    local state_file

    state_file=$(sw_state_file "$state")

    [ -f "$state_file" ] || return 0

    (
        sw_state_use "$state"

        sw_state_clear

        sw_state_load

        sw_state_set "message_from_module_${id}" "$value"
        sw_state_set "message_from_module_${id}.hidden" "true"
        sw_state_set "message_from_module_${id}.from" "$sender"

        case $persist in
            true|false)
                sw_state_set "message_from_module_${id}.persist" "$persist"
                ;;
            *)
                sw_state_set "message_from_module_${id}.persist" "false"
                ;;
        esac

        sw_state_save
    )
}

sw_message_load() {

    local id=$1

    local persist

    MESSAGE_FROM_MODULE=$(sw_state_get "message_from_module_${id}")

    [ -n "$MESSAGE_FROM_MODULE" ] || return 0

    persist=$(sw_state_get "message_from_module_${id}.persist")

    if [ "$persist" != "true" ]; then
        sw_state_delete_key "message_from_module_${id}"
        sw_state_delete_key "message_from_module_${id}.persist"
        sw_state_delete_key "message_from_module_${id}.hidden"
        sw_state_delete_key "message_from_module_${id}.from"
    fi
}
