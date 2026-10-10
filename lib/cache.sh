#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# funciones de cache todos los scripts de syswatch
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------



# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------


# -----------------------------------------------------------------------------
# Cache helpers
# -----------------------------------------------------------------------------

sw_cache_copy() {

    local name
    local file="$1"
    local dest

    [[ -f "${file}" ]] || {
        echo -1
        return 1
    }

    name=$(basename "$file")

    dest="$(sw_cache_file "${name}")"

    cp "$file" "$dest"

}

sw_cache_post() {

    local name="$1"
    local url="$2"
    local data="$3"

    shift 3

    curl \
        --silent \
        --show-error \
        --fail \
        --location \
        --request POST \
        --header "Content-Type: application/json" \
        "$@" \
        --data "${data}" \
        --output "$(sw_cache_file "${name}")" \
        "${url}"

}

sw_cache_download() {

    local name="$1"
    local url="$2"

    shift 2

    curl \
        --silent \
        --show-error \
        --location \
        "$@" \
        --output "$(sw_cache_file "${name}")" \
        "${url}"

}


sw_cache_file() {

    printf "%s/%s" "${CACHE_DIR}" "$1"

}

sw_cache_exists() {

    local name="$1"

    [[ -f "$(sw_cache_file "${name}")" ]]

}

sw_cache_age() {

    local name="$1"
    local file

    file="$(sw_cache_file "${name}")"

    [[ -f "${file}" ]] || {
        echo -1
        return
    }

    echo $(( $(date +%s) - $(stat -c %Y "${file}") ))

}

sw_cache_is_expired() {

    local name="$1"
    local max_age="$2"

    local age

    age="$(sw_cache_age "${name}")"

    (( age < 0 || age >= max_age ))

}

sw_cache_touch() {

    local name="$1"

    touch "$(sw_cache_file "${name}")"

}

sw_cache_remove() {

    local name="$1"

    rm -f "$(sw_cache_file "${name}")"

}

sw_cache_write() {

    local name="$1"

    cat > "$(sw_cache_file "${name}")"

}

sw_cache_read() {

    local name="$1"

    cat "$(sw_cache_file "${name}")"

}

