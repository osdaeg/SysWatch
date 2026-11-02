#!/usr/bin/env bash

CALDAV_TASK_COLLECTIONS=()
readonly CALDAV_TASK_CONFIG="${CONFIG_DIR}/caldavtask.conf"

caldavtask_discover_collections() {

    local response

    CALDAV_TASK_COLLECTIONS=()

    response="$(
        curl -fsS \
            --max-time 15 \
            -u "${CALDAV_USERNAME}:${CALDAV_PASSWORD}" \
            -X PROPFIND \
            -H 'Content-Type: application/xml; charset=utf-8' \
            -H 'Depth: 1' \
            --data-binary @- \
            "$CALDAV_URL" <<'EOF'
<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:"
    xmlns:C="urn:ietf:params:xml:ns:caldav">

    <D:prop>
        <D:resourcetype/>
        <D:displayname/>
        <C:supported-calendar-component-set/>
    </D:prop>

</D:propfind>
EOF
    )" || {

        CALDAV_ERROR="Unable to discover CalDAV task collections"
        return 1
    }

    if ! xmllint --noout - >/dev/null 2>&1 <<<"${response}"; then

        CALDAV_ERROR="Invalid CalDAV task discovery response"
        return 1

    fi

    local response_count
    local i

    response_count="$(
        xmllint \
            --xpath \
            'count(//*[local-name()="response"])' \
            - \
            <<<"${response}" \
            2>/dev/null
    )"

    for ((i = 1; i <= response_count; i++)); do

        local href
        local displayname
        local is_calendar
        local has_vtodo

        href="$(
            xmllint \
                --xpath \
                "string((//*[local-name()='response'])[${i}]/*[local-name()='href'])" \
                - \
                <<<"${response}" \
                2>/dev/null
        )"

        displayname="$(
            xmllint \
                --xpath \
                "string((//*[local-name()='response'])[${i}]//*[local-name()='displayname'])" \
                - \
                <<<"${response}" \
                2>/dev/null
        )"

        is_calendar="$(
            xmllint \
                --xpath \
                "count((//*[local-name()='response'])[${i}]//*[local-name()='resourcetype']/*[local-name()='calendar'])" \
                - \
                <<<"${response}" \
                2>/dev/null
        )"

        has_vtodo="$(
            xmllint \
                --xpath \
                "count((//*[local-name()='response'])[${i}]//*[local-name()='supported-calendar-component-set']/*[local-name()='comp'][@name='VTODO'])" \
                - \
                <<<"${response}" \
                2>/dev/null
        )"

        if [[ "${is_calendar}" -gt 0 && "${has_vtodo}" -gt 0 ]]; then

            CALDAV_TASK_COLLECTIONS+=(
                "${href}"$'\t'"${displayname}"
            )

        fi

    done
}

caldavtask_load_config() {

    local title=""
    local collection_url
    local enabled

    [[ -f "${CALDAV_TASK_CONFIG}" ]] || return 0

    while IFS= read -r line || [[ -n "${line}" ]]; do

        if [[ "${line}" == "# "* ]]; then
            title="${line#\# }"
            continue
        fi

        [[ -z "${line}" ]] && continue

        IFS='=' read -r collection_url enabled <<<"${line}"

        [[ -n "${collection_url}" ]] || continue
        [[ "${enabled}" == "true" ]] || continue

        printf '%s\t%s\n' \
            "${collection_url}" \
            "${title}"

    done <"${CALDAV_TASK_CONFIG}"
}

caldavtask_update_config() {

    local tmp_config
    local href
    local displayname
    local enabled
    local line
    local title=""
    local collection_url

    declare -A old_enabled
    declare -A old_title
    declare -A current_collections
    declare -a old_collections=()

    # Read existing configuration.
    if [[ -f "${CALDAV_TASK_CONFIG}" ]]; then

        while IFS= read -r line || [[ -n "${line}" ]]; do

            if [[ "${line}" == "# "* ]]; then
                title="${line#\# }"
                continue
            fi

            [[ -z "${line}" ]] && continue

            IFS='=' read -r collection_url enabled <<<"${line}"

            [[ -n "${collection_url}" ]] || continue

            old_enabled["${collection_url}"]="${enabled}"
            old_title["${collection_url}"]="${title}"
            old_collections+=("${collection_url}")

        done <"${CALDAV_TASK_CONFIG}"
    fi

    tmp_config="$(mktemp)" || return 1

    # Write discovered collections.
    for collection in "${CALDAV_TASK_COLLECTIONS[@]}"; do

        IFS=$'\t' read -r href displayname <<<"${collection}"

        [[ -n "${href}" ]] || continue

        current_collections["${href}"]=1

        enabled="${old_enabled[${href}]:-false}"

        printf '# %s\n' "${displayname}" >>"${tmp_config}"
        printf '%s=%s\n' "${href}" "${enabled}" >>"${tmp_config}"

    done

    # Preserve collections that disappeared from discovery.
    for href in "${old_collections[@]}"; do

        [[ -n "${current_collections[${href}]:-}" ]] && continue

        printf '# %s\n' "${old_title[${href}]}" >>"${tmp_config}"
        printf '%s=%s\n' \
            "${href}" \
            "${old_enabled[${href}]}" \
            >>"${tmp_config}"

    done

    mkdir -p "${CONFIG_DIR}" || {
        rm -f "${tmp_config}"
        return 1
    }

    mv "${tmp_config}" "${CALDAV_TASK_CONFIG}" || {
        rm -f "${tmp_config}"
        return 1
    }
}

caldavtask_get_tasks() {

    local collection_url="$1"
    local response
    local caldav_server
    local calendar_data

    caldav_server="$(
        sed -E 's#^(https?://[^/]+).*#\1#' <<<"${CALDAV_URL}"
    )"

    response="$(
        curl -fsS \
            --max-time 15 \
            -u "${CALDAV_USERNAME}:${CALDAV_PASSWORD}" \
            -X REPORT \
            -H 'Content-Type: application/xml; charset=utf-8' \
            -H 'Depth: 1' \
            --data-binary @- \
            "${caldav_server}${collection_url}" <<'EOF'
<?xml version="1.0" encoding="utf-8" ?>
<C:calendar-query
    xmlns:D="DAV:"
    xmlns:C="urn:ietf:params:xml:ns:caldav">

    <D:prop>
        <D:getetag/>
        <C:calendar-data/>
    </D:prop>

    <C:filter>
        <C:comp-filter name="VCALENDAR">
            <C:comp-filter name="VTODO"/>
        </C:comp-filter>
    </C:filter>

</C:calendar-query>
EOF
    )" || {

        CALDAV_ERROR="Unable to retrieve CalDAV tasks"
        return 1
    }

    if ! xmllint --noout - >/dev/null 2>&1 <<<"${response}"; then

        CALDAV_ERROR="Invalid CalDAV task response"
        return 1
    fi

    calendar_data="$(
        xmllint \
            --xpath \
            '//*[local-name()="calendar-data"]/text()' \
            - \
            <<<"${response}" \
            2>/dev/null
    )"

    awk '
        BEGIN {
            task_id = ""
            task_title = ""
            task_due = "-"
            task_status = ""
            task_percent = "0"
        }

        /^BEGIN:VTODO$/ {
            task_id = ""
            task_title = ""
            task_due = "-"
            task_status = ""
            task_percent = "0"
            in_task = 1
            next
        }

        /^END:VTODO$/ {
            if (in_task && task_id != "" && task_title != "") {
                printf "%s\t%s\t%s\t%s\t%s\n",
                    task_id,
                    task_title,
                    task_due,
                    task_status,
                    task_percent
            }

            in_task = 0
            next
        }

        !in_task {
            next
        }

        /^UID:/ {
            task_id = substr($0, 5)
            next
        }

        /^SUMMARY:/ {
            task_title = substr($0, 9)
            next
        }

        /^DUE(;[^:]*)?:/ {
    task_due = $0
    sub(/^DUE(;[^:]*)?:/, "", task_due)
    next
}

        /^STATUS:/ {
            task_status = substr($0, 8)
            next
        }

        /^PERCENT-COMPLETE:/ {
            task_percent = substr($0, 18)
            next
        }
    ' <<<"${calendar_data}"
}

caldavtask_collect() {

    local collection_url
    local collection_name
    local task
    local task_id
    local task_title
    local task_due
    local task_status
    local task_percent

    caldavtask_discover_collections || return 1

    caldavtask_update_config || return 1

    while IFS=$'\t' read -r collection_url collection_name; do

        [[ -n "${collection_url}" ]] || continue

        sw_task_list_begin \
            "CalDAV" \
            "${collection_url}" \
            "${collection_name}"

        while IFS=$'\t' read -r \
            task_id \
            task_title \
            task_due \
            task_status \
            task_percent; do

            [[ -n "${task_id}" ]] || continue
            [[ -n "${task_title}" ]] || continue

            if [[ "${task_due}" == "-" ]]; then
                task_due=""
            fi

            sw_task_add \
                "${task_id}" \
                "${task_title}" \
                "${task_due}" \
                "${task_status}" \
                "${task_percent}"

        done < <(
            caldavtask_get_tasks "${collection_url}"
        )

        sw_task_list_end

    done < <(
        caldavtask_load_config
    )
}
