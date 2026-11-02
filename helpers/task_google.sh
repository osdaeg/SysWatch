#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Google Tasks helper
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly GTASK_API="https://tasks.googleapis.com/tasks/v1"
readonly GTASK_TOKEN_URL="https://oauth2.googleapis.com/token"
readonly GTASK_LISTS_CONFIG="${CONFIG_DIR}/gtask_lists.conf"

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

GTASK_ACCESS_TOKEN=""

# -----------------------------------------------------------------------------
# Authentication
# -----------------------------------------------------------------------------

gtask_get_access_token() {

    local response

    response="$(curl -fsS \
        -w '\nHTTP_STATUS:%{http_code}' \
        -X POST \
        "${GTASK_TOKEN_URL}" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=refresh_token" \
        -d "refresh_token=${GCAL_TOKEN}" \
        -d "client_id=${GCAL_CLIENT_ID}" \
        -d "client_secret=${GCAL_CLIENT_SECRET}")" || return 1

    #echo "$response" | jq . > ~/scripts/syswatch/helpers/token.json

    GTASK_ACCESS_TOKEN="$(
        jq -r '.access_token // empty' <<<"${response}"
    )"

    [[ -n "${GTASK_ACCESS_TOKEN}" ]]

}

# -----------------------------------------------------------------------------
# Google Tasks API
# -----------------------------------------------------------------------------

gtask_get_lists() {

    local page_token=""
    local url
    local response
    local items='[]'

    while :; do

        url="${GTASK_API}/users/@me/lists?maxResults=100"

        if [[ -n "${page_token}" ]]; then
            url+="&pageToken=${page_token}"
        fi

        response="$(curl -fsS \
            -w '\nHTTP_STATUS:%{http_code}' \
            -X GET \
            "${url}" \
            -H "Authorization: Bearer ${GTASK_ACCESS_TOKEN}" \
            -H "Accept: application/json")" || return 1

        #echo "=====" >> ~/scripts/syswatch/helpers/token.json
        #echo "$response" | jq . >> ~/scripts/syswatch/helpers/token.json

        items="$(
            jq -c \
                --argjson new "$(jq '.items // []' <<<"${response}")" \
                '. + $new' \
                <<<"${items}"
        )"

        page_token="$(
            jq -r '.nextPageToken // empty' <<<"${response}"
        )"

        [[ -z "${page_token}" ]] && break

    done

    printf '%s\n' "${items}"

}

gtask_get_tasks() {

    local list_id="$1"
    local page_token=""
    local url
    local response

    while :; do

        url="${GTASK_API}/lists/${list_id}/tasks?maxResults=100&showCompleted=true&showHidden=false"

        if [[ -n "${page_token}" ]]; then
            url+="&pageToken=${page_token}"
        fi

        response="$(curl -fsS \
            -X GET \
            "${url}" \
            -H "Authorization: Bearer ${GTASK_ACCESS_TOKEN}" \
            -H "Accept: application/json")" || return 1

        jq -c '.items[]?' <<<"${response}"

        page_token="$(
            jq -r '.nextPageToken // empty' <<<"${response}"
        )"

        [[ -z "${page_token}" ]] && break

    done

}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

gtask_update_config() {

    local lists="$1"
    local tmp_file
    local list_id
    local title
    local enabled

    [[ -n "${lists}" ]] || return 0

    mkdir -p "$(dirname "${GTASK_LISTS_CONFIG}")" || return 1

    tmp_file="$(mktemp)" || return 1

    while IFS=$'\t' read -r list_id title; do

        [[ -n "${list_id}" ]] || continue

        enabled="false"

        if [[ -f "${GTASK_LISTS_CONFIG}" ]]; then

            enabled="$(
                awk -F= -v id="${list_id}" '
                    $1 == id {
                        print $2
                        exit
                    }
                ' "${GTASK_LISTS_CONFIG}"
            )"

            [[ "${enabled}" == "true" ]] || enabled="false"

        fi

        printf '# %s\n' "${title}" >>"${tmp_file}"
        printf '%s=%s\n' "${list_id}" "${enabled}" >>"${tmp_file}"

    done < <(
        jq -r '.[] | [.id, .title] | @tsv' <<<"${lists}"
    )

    mv "${tmp_file}" "${GTASK_LISTS_CONFIG}"

}

gtask_load_config() {
    local title=""
    local list_id
    local enabled

    [[ -f "${GTASK_LISTS_CONFIG}" ]] || return 0

    while IFS= read -r line || [[ -n "${line}" ]]; do
        # Comentario = título de la lista
        if [[ "${line}" == "# "* ]]; then
            title="${line#\# }"
            continue
        fi

        # Ignorar líneas vacías
        [[ -z "${line}" ]] && continue

        IFS='=' read -r list_id enabled <<<"${line}"

        [[ -n "${list_id}" ]] || continue
        [[ "${enabled}" == "true" ]] || continue

        printf '%s\t%s\n' "${list_id}" "${title}"
    done <"${GTASK_LISTS_CONFIG}"
}

# -----------------------------------------------------------------------------
# Task collection
# -----------------------------------------------------------------------------

gtask_collect() {

    local lists
    local list_id
    local list_title
    local task
    local task_id
    local task_title
    local task_due
    local task_status
    local task_percent

    gtask_get_access_token || return 1

    lists="$(
        gtask_get_lists
    )" || return 1

    gtask_update_config "${lists}" || return 1

    while IFS=$'\t' read -r list_id list_title; do

        [[ -n "${list_id}" ]] || continue

        sw_task_list_begin \
            "Google Tasks" \
            "${list_id}" \
            "${list_title}"

        while IFS= read -r task; do

            task_id="$(
                jq -r '.id // empty' <<<"${task}"
            )"

            task_title="$(
                jq -r '.title // empty' <<<"${task}"
            )"

            task_due="$(
                jq -r '.due // empty' <<<"${task}"
            )"

            task_status="$(
                jq -r '.status // "needsAction"' <<<"${task}"
            )"

            task_percent=0

            if [[ "${task_status}" == "completed" ]]; then
                task_percent=100
            fi

            [[ -n "${task_id}" ]] || continue
            [[ -n "${task_title}" ]] || continue

            sw_task_add \
                "${task_id}" \
                "${task_title}" \
                "${task_due}" \
                "${task_status}" \
                "${task_percent}"

        done < <(
            gtask_get_tasks "${list_id}"
        )

        sw_task_list_end

    done < <(
        gtask_load_config
    )
}
