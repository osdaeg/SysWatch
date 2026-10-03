#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# journal module
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Journal"
readonly MODULE_DESCRIPTION="Detects relevant system journal events"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-1100}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly JOURNAL_MAX_PROBLEMS="${JOURNAL_MAX_PROBLEMS:-10}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

JOURNAL_COUNT=0
JOURNAL_STATUS="${SW_STATUS_UNKNOWN}"
JOURNAL_DETAILS=""
JOURNAL_CURSOR=""

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

journal_get_last_cursor() {

    journalctl \
        -n 1 \
        -o json \
        --no-pager \
        2>/dev/null |
        python3 -c '
import sys
import json

line = sys.stdin.readline()

if not line:
    sys.exit(0)

try:
    data = json.loads(line)
    print(data.get("__CURSOR", ""))
except Exception:
    sys.exit(1)
'

}

journal_collect() {

    JOURNAL_COUNT=0
    JOURNAL_DETAILS=""
    JOURNAL_CURSOR=""

    local state_cursor
    state_cursor=$(sw_state_get "cursor")

    # -------------------------------------------------------------------------
    # First execution:
    #
    # Do not process the entire journal history. Start watching from the
    # current last entry.
    # -------------------------------------------------------------------------

    if [[ -z "$state_cursor" ]]; then

        JOURNAL_CURSOR=$(journal_get_last_cursor)

        if [[ -z "$JOURNAL_CURSOR" ]]; then
            return 0
        fi

        return 0

    fi

    # -------------------------------------------------------------------------
    # Read only events after the saved cursor.
    # -------------------------------------------------------------------------

    local journal_output

    journal_output=$(

        journalctl \
            --after-cursor "$state_cursor" \
            -o json \
            --no-pager \
            2>/dev/null

    ) || return 1

    [[ -z "$journal_output" ]] && {
        JOURNAL_CURSOR="$state_cursor"
        return 0
    }

    # -------------------------------------------------------------------------
    # Parse JSON records.
    #
    # Python is used only for JSON parsing. journalctl itself remains the
    # source of truth for the journal.
    # -------------------------------------------------------------------------

    local parsed

    parsed=$(
        printf '%s\n' "$journal_output" |
            JOURNAL_PRIORITY_FILTER="$JOURNAL_PRIORITY_FILTER" \
                JOURNAL_PATTERN_FILTER="$JOURNAL_PATTERN_FILTER" \
                JOURNAL_MESSAGE_FILTER="$JOURNAL_MESSAGE_FILTER" \
                python3 -c '
import sys
import json
import re
import os

MAX_MESSAGE_LENGTH = 160

priority_filter = os.environ.get(
    "JOURNAL_PRIORITY_FILTER",
    "<=4"
).strip()

pattern_filter_enabled = (
    os.environ.get(
        "JOURNAL_PATTERN_FILTER",
        "true"
    ).lower() == "true"
)

message_filter = os.environ.get(
    "JOURNAL_MESSAGE_FILTER",
    ""
).strip()

patterns = None

if pattern_filter_enabled and message_filter:
    try:
        patterns = re.compile(
            message_filter,
            re.IGNORECASE
        )
    except re.error:
        patterns = None


def priority_matches(priority):

    match = re.fullmatch(
        r"(<=|>=|<|>|=)?\s*(\d+)",
        priority_filter
    )

    if not match:
        return False

    operator = match.group(1) or "="
    value = int(match.group(2))

    if operator == "<":
        return priority < value

    if operator == "<=":
        return priority <= value

    if operator == ">":
        return priority > value

    if operator == ">=":
        return priority >= value

    return priority == value


for line in sys.stdin:

    try:
        data = json.loads(line)
    except Exception:
        continue

    message = data.get("MESSAGE", "")

    if isinstance(message, list):
        message = "".join(str(part) for part in message)
    else:
        message = str(message)

    message = message.replace("\n", " ").strip()

    message = re.sub(
        r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\s+",
        "",
        message
    )

    priority = data.get("PRIORITY", "")
    unit = data.get("_SYSTEMD_UNIT", "")
    comm = data.get("_COMM", "")
    cursor = data.get("__CURSOR", "")

    try:
        priority_num = int(priority)
    except Exception:
        priority_num = 6

    priority_match = priority_matches(priority_num)

    pattern_match = (
        pattern_filter_enabled
        and patterns is not None
        and patterns.search(message) is not None
    )

    relevant = priority_match or pattern_match

    if not relevant:
        continue

    source = unit or comm or "journal"

    if len(message) > MAX_MESSAGE_LENGTH:
        message = message[:MAX_MESSAGE_LENGTH - 3] + "..."

    print(
        source + "\t" +
        message + "\t" +
        priority + "\t" +
        cursor
    )
'
    ) || return 1

    # -------------------------------------------------------------------------
    # Process relevant events.
    #
    # Identical messages are grouped together.
    # -------------------------------------------------------------------------

    local last_cursor=""
    local line
    local source
    local message
    local priority
    local cursor

    declare -A problem_count
    declare -A problem_source
    declare -A problem_priority

    local problem_total=0

    while IFS=$'\t' read -r source message priority cursor; do

        [[ -z "$cursor" ]] && continue

        last_cursor="$cursor"

        local key="${source}|${message}"

        if [[ -v "problem_count[$key]" ]]; then
            ((problem_count["$key"]++))
        else
            problem_count["$key"]=1
            ((problem_total++))
        fi

        problem_source["$key"]="$source"
        problem_priority["$key"]="$priority"

    done <<<"$parsed"

    # -------------------------------------------------------------------------
    # Always advance the cursor to the newest journal entry, not merely the
    # newest relevant problem.
    #
    # Otherwise harmless journal messages would be processed again forever.
    # -------------------------------------------------------------------------

    JOURNAL_CURSOR=$(journal_get_last_cursor)

    # If we did not find a newer cursor, keep the previous one.
    [[ -z "$JOURNAL_CURSOR" ]] && JOURNAL_CURSOR="$state_cursor"

    # -------------------------------------------------------------------------
    # Build details.
    # -------------------------------------------------------------------------

    local key
    local count
    local details=""

    for key in "${!problem_count[@]}"; do

        count="${problem_count[$key]}"
        source="${problem_source[$key]}"
        message="${key#*|}"

        details+="${source}<br>"

        if ((count > 1)); then
            details+="${message} ×${count}<br><br>"
        else
            details+="${message}<br><br>"
        fi

    done

    JOURNAL_COUNT="${problem_total}"
    JOURNAL_DETAILS="${details}"

}

journal_analyze() {

    JOURNAL_STATUS="${SW_STATUS_OK}"

    if ((JOURNAL_COUNT > 0)); then

        JOURNAL_STATUS="${SW_STATUS_WARNING}"

    fi

}

journal_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "$(sw_translate "Journal")"
    sw_state_set "module.icon" "lucide/book-open"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Data
    # -------------------------------------------------------------------------

    sw_state_set "count" "${JOURNAL_COUNT}"

    sw_state_set "count.label" "$(sw_translate "New issues")"
    sw_state_set "count.widget" "value"
    sw_state_set "count.order" "10"

    if [[ -n "$JOURNAL_DETAILS" ]]; then
        sw_state_set "details" "${JOURNAL_DETAILS}"
    else
        sw_state_set "details" " "
    fi

    # Cursor is deliberately kept in the module state.
    sw_state_set "cursor" "${JOURNAL_CURSOR}"
    sw_state_set "cursor.hidden" "true"

}

journal_report() {

    sw_log_info \
        "${MODULE_NAME}" \
        "New problems: ${JOURNAL_COUNT} (${JOURNAL_STATUS})"

}

sw_module_run() {

    sw_state_use "journal"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    journal_collect || return 1

    journal_analyze

    sw_status_update "${JOURNAL_STATUS}" || return 1

    journal_update_state

    sw_state_save

    journal_report

}
