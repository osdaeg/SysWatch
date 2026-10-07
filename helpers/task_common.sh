#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# task helper
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Task lists
# -----------------------------------------------------------------------------

declare -a SW_TASK_LIST_IDS=()
declare -a SW_TASK_LIST_NAMES=()
declare -a SW_TASK_LIST_SOURCES=()
declare -a SW_TASK_LIST_TASKS=()

# -----------------------------------------------------------------------------
# Tasks
# -----------------------------------------------------------------------------

declare -a SW_TASK_IDS=()
declare -a SW_TASK_TITLES=()
declare -a SW_TASK_DUES=()
declare -a SW_TASK_STATUSES=()
declare -a SW_TASK_PERCENTS=()

# -----------------------------------------------------------------------------
# Current list
# -----------------------------------------------------------------------------

SW_TASK_CURRENT_SOURCE=""
SW_TASK_CURRENT_ID=""
SW_TASK_CURRENT_NAME=""
SW_TASK_CURRENT_TASKS=()

# -----------------------------------------------------------------------------
# Reset
# -----------------------------------------------------------------------------

sw_task_reset() {

    SW_TASK_LIST_IDS=()
    SW_TASK_LIST_NAMES=()
    SW_TASK_LIST_SOURCES=()
    SW_TASK_LIST_TASKS=()

    SW_TASK_IDS=()
    SW_TASK_TITLES=()
    SW_TASK_DUES=()
    SW_TASK_STATUSES=()
    SW_TASK_PERCENTS=()

    SW_TASK_CURRENT_SOURCE=""
    SW_TASK_CURRENT_ID=""
    SW_TASK_CURRENT_NAME=""
    SW_TASK_CURRENT_TASKS=()

}

# -----------------------------------------------------------------------------
# Start a task list
#
# Usage:
#
#   sw_task_list_begin "source" "list_id" "list_name"
# -----------------------------------------------------------------------------

sw_task_list_begin() {

    SW_TASK_CURRENT_SOURCE="$1"
    SW_TASK_CURRENT_ID="$2"
    SW_TASK_CURRENT_NAME="$3"

    SW_TASK_CURRENT_TASKS=()

}

# -----------------------------------------------------------------------------
# Add a task to the current list
#
# Usage:
#
#   sw_task_add \
#       "task_id" \
#       "title" \
#       "due" \
#       "status" \
#       "percent"
# -----------------------------------------------------------------------------

sw_task_add() {

    local task_index

    task_index="${#SW_TASK_IDS[@]}"

    SW_TASK_IDS[task_index]="$1"
    SW_TASK_TITLES[task_index]="$2"
    SW_TASK_DUES[task_index]="$3"
    SW_TASK_STATUSES[task_index]="$4"
    SW_TASK_PERCENTS[task_index]="${5:-0}"

    SW_TASK_CURRENT_TASKS+=("$task_index")

}

# -----------------------------------------------------------------------------
# Finish the current task list
# -----------------------------------------------------------------------------

sw_task_list_end() {

    local list_index

    list_index="${#SW_TASK_LIST_IDS[@]}"

    SW_TASK_LIST_IDS[list_index]="$SW_TASK_CURRENT_ID"
    SW_TASK_LIST_NAMES[list_index]="$SW_TASK_CURRENT_NAME"
    SW_TASK_LIST_SOURCES[list_index]="$SW_TASK_CURRENT_SOURCE"
    SW_TASK_LIST_TASKS[list_index]="${SW_TASK_CURRENT_TASKS[*]}"

    SW_TASK_CURRENT_SOURCE=""
    SW_TASK_CURRENT_ID=""
    SW_TASK_CURRENT_NAME=""
    SW_TASK_CURRENT_TASKS=()

}

# -----------------------------------------------------------------------------
# List count
# -----------------------------------------------------------------------------

sw_task_list_count() {

    printf '%s\n' "${#SW_TASK_LIST_IDS[@]}"

}

# -----------------------------------------------------------------------------
# Task count
#
# Returns the total number of collected tasks.
# -----------------------------------------------------------------------------

sw_task_count() {

    printf '%s\n' "${#SW_TASK_IDS[@]}"

}
