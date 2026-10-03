#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# RSS feed monitor
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="RSS"
readonly MODULE_DESCRIPTION="RSS feed monitor"
readonly MODULE_VERSION="0.1.0"

MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-10}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly RSS_SOURCES="${RSS_SOURCES:-}"
readonly RSS_ARTICLES_TO_DISPLAY="${RSS_ARTICLES_TO_DISPLAY:-8}"
readonly RSS_HISTORY="${RSS_HISTORY:-1000}"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

RSS_FEED_TITLE=""
RSS_NEW_ARTICLES=0
RSS_STATUS="${SW_STATUS_UNKNOWN}"

declare -a RSS_ARTICLES=()
declare -a RSS_NEW_GUIDS=()
declare -a RSS_KNOWN_GUIDS=()
declare -A RSS_KNOWN=()

# -----------------------------------------------------------------------------
# Reset
# -----------------------------------------------------------------------------

rss_reset() {

    RSS_FEED_TITLE=""
    RSS_NEW_ARTICLES=0
    RSS_STATUS="${SW_STATUS_UNKNOWN}"

    RSS_ARTICLES=()
    RSS_NEW_GUIDS=()
    RSS_KNOWN_GUIDS=()
    RSS_KNOWN=()

}

# -----------------------------------------------------------------------------
# Collect
# -----------------------------------------------------------------------------

rss_url_is_ignored() {

    local url="$1"
    local pattern

    IFS=',' read -ra patterns <<<"$RSS_PATTERNS_TO_IGNORE"

    for pattern in "${patterns[@]}"; do

        [[ -z "$pattern" ]] && continue

        if [[ "$url" == *"$pattern"* ]]; then
            return 0
        fi

    done

    return 1

}

rss_collect() {

    local source="$1"
    local output

    local field1
    local field2
    local field3
    local field4

    local guid
    local url
    local title
    local pubdate

    output=$(python3 \
        "$HELPERS_DIR/rss_parser.py" \
        "$source") || return 1

    while IFS=$'\t' read -r field1 field2 field3 field4; do

        if [[ "$field1" == "__FEED_TITLE__" ]]; then

            RSS_FEED_TITLE="$field2"
            continue

        fi

        guid="$field1"
        url="$field2"
        title="$field3"
        pubdate="$field4"

        [[ -n "$guid" ]] || continue
        [[ -n "$url" ]] || continue
        [[ -n "$title" ]] || continue

        if rss_url_is_ignored "$url"; then
            continue
        fi

        RSS_ARTICLES+=(
            "$guid"$'\t'"$url"$'\t'"$title"$'\t'"$pubdate"
        )

    done <<<"$output"

    [[ -n "$RSS_FEED_TITLE" ]] || return 1

}

# -----------------------------------------------------------------------------
# Load history
# -----------------------------------------------------------------------------

rss_load_history() {
    local total
    local i
    local guid

    total=$(sw_state_get "rss.known.count")
    [[ "$total" =~ ^[0-9]+$ ]] || total=0

    for ((i = 1; i <= total; i++)); do
        guid=$(sw_state_get "rss.known.${i}")

        [[ -n "$guid" ]] || continue

        RSS_KNOWN_GUIDS+=("$guid")
        RSS_KNOWN["$guid"]=1

    done

}

# -----------------------------------------------------------------------------
# Analyze
# -----------------------------------------------------------------------------

rss_analyze() {

    local article
    local guid

    RSS_NEW_ARTICLES=0
    RSS_NEW_GUIDS=()

    for article in "${RSS_ARTICLES[@]}"; do

        IFS=$'\t' read -r guid _ <<<"$article"

        #[[ -n "${RSS_KNOWN["$guid"]-}" ]] && continue

        if [[ -n "${RSS_KNOWN["$guid"]-}" ]]; then
            continue
        else
            echo "NUEVO:    [$guid]" >&2
        fi

        ((RSS_NEW_ARTICLES++))
        RSS_NEW_GUIDS+=("$guid")

    done

    if ((RSS_NEW_ARTICLES > 0)); then
        RSS_STATUS="${SW_STATUS_INFO}"
    else
        RSS_STATUS="${SW_STATUS_OK}"
    fi
}

# -----------------------------------------------------------------------------
# Update state
# -----------------------------------------------------------------------------

rss_update_state() {

    local article
    local guid
    local url
    local title
    local pubdate

    local i=0

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.label" "$(sw_translate "${RSS_FEED_TITLE}")"
    sw_state_set "module.icon" "lucide/rss"
    sw_state_set "module.order" "$MODULE_ORDER"

    sw_state_set "new_articles" "${RSS_NEW_ARTICLES}"
    sw_state_set "new_articles.label" "$(sw_translate "New:")"
    sw_state_set "new_articles.order" "10"

    for ((i = 1; i <= RSS_ARTICLES_TO_DISPLAY; i++)); do

        sw_state_set "article.${i}" ""
        sw_state_set "article.${i}.label" "$(sw_translate "")"

    done

    i=0

    for article in "${RSS_ARTICLES[@]}"; do

        ((i >= RSS_ARTICLES_TO_DISPLAY)) && break

        IFS=$'\t' read -r guid url title pubdate <<<"$article"

        ((i++))

        sw_state_set \
            "article.${i}" \
            "<a href=\"${url}\">${title}</a>"

        sw_state_set \
            "article.${i}.label" \
            "${i}"

    done

}

# -----------------------------------------------------------------------------
# Update history
# -----------------------------------------------------------------------------

rss_update_history() {

    local -a history=()
    local -A seen=()

    local guid
    local i
    local total

    #
    # New GUIDs first.
    #

    for guid in "${RSS_NEW_GUIDS[@]}"; do

        [[ -n "$guid" ]] || continue
        [[ -n "${seen[$guid]+x}" ]] && continue

        history+=("$guid")
        seen["$guid"]=1

    done

    #
    # Then previous history.
    #

    for guid in "${RSS_KNOWN_GUIDS[@]}"; do

        [[ -n "$guid" ]] || continue
        [[ -n "${seen[$guid]+x}" ]] && continue

        history+=("$guid")
        seen["$guid"]=1

    done

    total=${#history[@]}

    ((total > RSS_HISTORY)) && total=$RSS_HISTORY

    sw_state_set "rss.known.count" "$total"
    sw_state_set "rss.known.count.hidden" "true"

    for ((i = 0; i < total; i++)); do

        sw_state_set \
            "rss.known.$((i + 1))" \
            "${history[$i]}"

        sw_state_set \
            "rss.known.$((i + 1)).hidden" \
            "true"

    done

}

# -----------------------------------------------------------------------------
# Module
# -----------------------------------------------------------------------------

sw_module_run() {

    local source

    [[ -n "$RSS_SOURCES" ]] || return 0

    IFS=',' read -ra sources <<<"$RSS_SOURCES"

    for source in "${sources[@]}"; do

        source="${source#"${source%%[![:space:]]*}"}"
        source="${source%"${source##*[![:space:]]}"}"

        [[ -n "$source" ]] || continue

        rss_reset

        #
        # Everything starts with this source.
        #

        rss_collect "$source" || continue

        #
        # The feed title becomes the state name.
        #

        sw_state_use "$RSS_FEED_TITLE"

        if [[ -n "$MODULE_REMOTE" ]]; then
            sw_state_remote "$MODULE_REMOTE"
        fi

        sw_state_load

        #
        # Now that we have the correct state, load its history
        # and determine which articles are new.
        #

        rss_load_history

        rss_analyze

        sw_status_update \
            "$RSS_STATUS" \
            "$RSS_FEED_TITLE" || continue

        rss_update_state
        rss_update_history

        sw_state_save

    done

}
