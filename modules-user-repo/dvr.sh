#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# Hikvision DVR camera snapshot module
#
# One .state per camera (like disk.sh/temperature.sh). On a failed
# snapshot attempt, the PREVIOUS good image is left showing rather than
# blanked out -- a stale picture is more useful than none.
#
# DVR_API_PATH is deliberately config, not auto-detected: it's a fixed
# property of your specific DVR's firmware, never changes between runs,
# so there's nothing to gain from re-probing it every cycle (only cost:
# doubled auth negotiation with --anyauth on every single run, forever,
# for something you can already confirm once with a manual curl).
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Dvr"
readonly MODULE_DESCRIPTION="Hikvision DVR camera snapshot monitoring"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-120}
MODULE_ORDER=${MODULE_ORDER:-70}
MODULE_REMOTE=${MODULE_REMOTE:-""}


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly DVR_URL="${DVR_URL:-}"
readonly DVR_USER="${DVR_USER:-}"
readonly DVR_PASSWORD="${DVR_PASSWORD:-}"

# "ISAPI" (modern firmware) or "PSIA" (older firmware, e.g. ~2015 units).
# Fixed for a given DVR -- confirm once by hand, then set it here.
readonly DVR_API_PATH="${DVR_API_PATH:-ISAPI}"

# Comma-separated "channel:name" pairs, e.g. "101:Terraza,201:Living".
readonly DVR_CAMERAS="${DVR_CAMERAS:-}"

readonly DVR_TIMEOUT_SECONDS="${DVR_TIMEOUT_SECONDS:-15}"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

dvr_camera_key() {

    local name="$1"

    local key="${name,,}"
    key="${key//[^a-z0-9_]/_}"

    printf 'dvr_%s\n' "${key}"

}

dvr_process_camera() {

    local channel="$1"
    local name="$2"

    local key
    key="$(dvr_camera_key "${name}")"

    sw_state_use "${key}"
    sw_state_load

    local tmp_file
    tmp_file="$(mktemp)"

    local http_code
    http_code="$(
        curl \
            --silent \
            --show-error \
            --anyauth \
            -u "${DVR_USER}:${DVR_PASSWORD}" \
            --max-time "${DVR_TIMEOUT_SECONDS}" \
            -o "${tmp_file}" \
            -w '%{http_code}' \
            "${DVR_URL}/${DVR_API_PATH}/Streaming/channels/${channel}/picture" \
            2>/dev/null
    )"

    local status
    local detail

    if [[ "${http_code}" == "200" && -s "${tmp_file}" ]]; then

        status="${SW_STATUS_OK}"
        detail="$(sw_translate "Snapshot updated")"

        sw_mkdir "${HTML_DIR}/images"
        mv "${tmp_file}" "${HTML_DIR}/images/${key}.jpg"

        # mktemp creates files mode 600 by default, and mv preserves
        # that -- nginx (running as its own user, not this one) can't
        # read a file only its owner can read. Without this, the image
        # exists at the right path with the right name and still shows
        # as broken in the browser.
        chmod 644 "${HTML_DIR}/images/${key}.jpg"

    else

        status="${SW_STATUS_CRITICAL}"
        detail="$(printf "$(sw_translate "The snapshot could not be obtained. (HTTP %sh)")\n" \
                "${http_code:-sin respuesta}")"

        rm -f "${tmp_file}"

    fi

    sw_status_update "${status}" "${key}" || return

    sw_state_set "module_version" "${MODULE_VERSION}"

    sw_state_set "module.label" "${name}"
    sw_state_set "module.icon" "lucide/cctv"
    sw_state_set "module.order" "$MODULE_ORDER"

    # Only set on success -- a failed attempt leaves whatever snapshot
    # was already loaded from the previous run untouched, instead of
    # blanking the card out.
    if [[ "${status}" == "${SW_STATUS_OK}" ]]; then

        sw_state_set "snapshot" "${key}.jpg"
        sw_state_set "snapshot.widget" "image"
        sw_state_set "snapshot.label" "${name}"
        sw_state_set "snapshot.order" "10"

    fi

    sw_state_set "detail" "${detail}"
    sw_state_set "detail.label" "$(sw_translate "Status")"
    sw_state_set "detail.order" "20"

    if [[ "${status}" == "${SW_STATUS_OK}" ]]; then

        sw_state_set "detail.hidden" "true"

    else

        sw_state_set "detail.hidden" "false"

    fi

    sw_state_save

    sw_log_info \
        "${MODULE_NAME}" \
        "DVR[${name}]: channel=${channel} http=${http_code} (${status})"

}

sw_module_run() {

    sw_require_command curl || return 127

    if [[ -z "${DVR_URL}" || -z "${DVR_USER}" || -z "${DVR_PASSWORD}" ]]; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "DVR_URL/DVR_USER/DVR_PASSWORD are not fully set"

        return 1

    fi

    if [[ -z "${DVR_CAMERAS}" ]]; then

        sw_log_warning \
            "${MODULE_NAME}" \
            "DVR_CAMERAS is not set, nothing to watch"

        return 1

    fi

    local pairs=()
    IFS=',' read -ra pairs <<< "${DVR_CAMERAS}"

    local pair
    local channel
    local name

    for pair in "${pairs[@]}"; do

        [[ -z "${pair}" ]] && continue

        channel="${pair%%:*}"
        name="${pair#*:}"

        dvr_process_camera "${channel}" "${name}"

    done

}
