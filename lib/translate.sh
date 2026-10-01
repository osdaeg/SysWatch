#!/usr/bin/env bash
#
# SysWatch translations
#

declare -A TRANSLATIONS

SW_TRANSLATIONS_LANG="${SW_TRANSLATIONS_LANG:-es}"

readonly SW_TRANSLATIONS_PENDING="${TRANSLATIONS_DIR}/pending"

# ------------------------------------------------------------
# Return the translations file path
# ------------------------------------------------------------

sw_translations_file() {

    printf '%s/%s.conf' \
        "${TRANSLATIONS_DIR}" \
        "${SW_TRANSLATIONS_LANG}"

}

# ------------------------------------------------------------
# Check whether the translations file exists
# ------------------------------------------------------------

sw_translations_exists() {

    [[ -f "$(sw_translations_file)" ]]

}

# ------------------------------------------------------------
# Load translations into the associative array
# ------------------------------------------------------------

sw_translations_load() {

    local file
    local line
    local key=""
    local count=1

    file="$(sw_translations_file)"

    sw_translations_exists || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do

        if ((count % 2 != 0)); then

            # Odd line: English key
            if [[ "$line" =~ ^en:(.*)$ ]]; then
                key="${BASH_REMATCH[1]}"
            else
                printf 'Warning: line %d does not start with "en:".\n' \
                    "$count" >&2
                key=""
            fi

        else

            # Even line: translation
            if [[ -n "$key" ]]; then

                if [[ "$line" =~ ^"${SW_TRANSLATIONS_LANG}":(.*)$ ]]; then
                    TRANSLATIONS["$key"]="${BASH_REMATCH[1]}"
                else
                    printf 'Warning: line %d does not start with "es:". Pair discarded.\n' \
                        "$count" >&2
                fi

            fi

            key=""

        fi

        ((count++))

    done <"$file"

}

# ------------------------------------------------------------
# Register an unknown translation key
#
# Only writes to pending if the key is not already registered.
# ------------------------------------------------------------

sw_translations_pending_add() {

    local chain="$1"

    [[ -n "$chain" ]] || return 1

    mkdir -p "${TRANSLATIONS_DIR}"

    # Avoid duplicate entries.
    if grep -Fqx -- "$chain" "$SW_TRANSLATIONS_PENDING" 2>/dev/null; then
        return 0
    fi

    printf '%s\n' "$chain" >>"$SW_TRANSLATIONS_PENDING"

}

# ------------------------------------------------------------
# Translate a string
#
# If the translation exists, return it.
# Otherwise return the original string and register it as pending.
# ------------------------------------------------------------

sw_translate() {

    local chain="$1"

    if [[ -z "$chain" ]]; then
        printf '%s\n' ""
        return 1
    fi

    if [[ -v 'TRANSLATIONS[$chain]' ]]; then

        if [[ -n "${TRANSLATIONS[$chain]}" ]]; then
            printf '%s\n' "${TRANSLATIONS[$chain]}"
        else
            printf '%s\n' "$chain"
        fi

        return 0
    fi

    sw_translations_pending_add "$chain"

    printf '%s\n' "$chain"

}

# ------------------------------------------------------------
# Save pending translation keys
#
# New keys are appended to the language file.
# Existing keys are ignored.
# ------------------------------------------------------------

sw_translations_save() {

    local file
    local chain

    file="$(sw_translations_file)"

    mkdir -p "${TRANSLATIONS_DIR}"

    touch "$file"

    [[ -f "$SW_TRANSLATIONS_PENDING" ]] || return 0

    while IFS= read -r chain || [[ -n "$chain" ]]; do

        [[ -n "$chain" ]] || continue

        # Already defined in the translations file.
        if grep -Fqx -- "en:${chain}" "$file"; then
            continue
        fi

        printf 'en:%s\n' "$chain" >>"$file"
        printf '%s:\n' "${SW_TRANSLATIONS_LANG}" >>"$file"

    done <"$SW_TRANSLATIONS_PENDING"

    rm -f "$SW_TRANSLATIONS_PENDING"

}
