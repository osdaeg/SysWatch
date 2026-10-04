#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# email module
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Email"
readonly MODULE_DESCRIPTION="Email unread messages monitor"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-1000}
MODULE_REMOTE=${MODULE_REMOTE:-""}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly EMAIL_CONFIG="${PROJECT_DIR}/config/email.conf"

# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

declare -a EMAIL_PROVIDERS=()

declare -A EMAIL_UNREAD
declare -A EMAIL_NEW
declare -A EMAIL_UIDS
declare -A EMAIL_STATUS

EMAIL_STATUS_GLOBAL="${SW_STATUS_UNKNOWN}"

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

email_load_previous() {
    local provider="$1"
    local cache_file
    local previous_uids=""
    local current_uids="${EMAIL_UIDS[$provider]:-}"

    cache_file="$(sw_cache_file "email-${provider}.uids")"

    # Primera ejecución: establecer referencia sin contar todo como nuevo.
    if ! sw_cache_exists "email-${provider}.uids"; then
        EMAIL_NEW["$provider"]=0
        return 0
    fi

    previous_uids="$(cat "$cache_file")"

    local current_uid
    local previous_uid
    local is_new
    local new_count=0

    for current_uid in $current_uids; do
        is_new=true

        for previous_uid in $previous_uids; do
            if [[ "$current_uid" == "$previous_uid" ]]; then
                is_new=false
                break
            fi
        done

        if [[ "$is_new" == true ]]; then
            ((new_count++))
        fi
    done

    EMAIL_NEW["$provider"]="$new_count"
}

email_save_cache() {

    local provider="$1"
    local cache_file

    cache_file="$(sw_cache_file "email-${provider}.uids")"

    printf '%s\n' "${EMAIL_UIDS[$provider]:-}" >"$cache_file"

}

email_load_config() {

    EMAIL_PROVIDERS=()

    [[ -f "$EMAIL_CONFIG" ]] || return 0

    local section=""
    local line

    while IFS= read -r line || [[ -n "$line" ]]; do

        # Remove comments and surrounding whitespace.
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^\[([A-Za-z0-9_-]+)\]$ ]]; then

            section="${BASH_REMATCH[1]}"
            EMAIL_PROVIDERS+=("$section")

        fi

    done <"$EMAIL_CONFIG"

}

email_get_config() {

    local provider="$1"
    local key="$2"

    local section=""
    local line
    local value

    while IFS= read -r line || [[ -n "$line" ]]; do

        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^\[([A-Za-z0-9_-]+)\]$ ]]; then

            section="${BASH_REMATCH[1]}"
            continue

        fi

        [[ "$section" == "$provider" ]] || continue

        if [[ "$line" =~ ^${key}[[:space:]]*=[[:space:]]*(.*)$ ]]; then

            value="${BASH_REMATCH[1]}"

            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"

            printf '%s' "$value"
            return 0

        fi

    done <"$EMAIL_CONFIG"

    return 1

}

email_get_env_value() {

    local variable="$1"

    [[ -n "$variable" ]] || return 1

    # Indirect expansion.
    printf '%s' "${!variable:-}"

}

email_provider_enabled() {

    local provider="$1"

    local protocol
    local username_env
    local password_env
    local username
    local password
    local path

    protocol="$(email_get_config "$provider" "protocol")"

    case "$protocol" in

    imap)

        username_env="$(email_get_config "$provider" "username_env")"
        password_env="$(email_get_config "$provider" "password_env")"

        username="$(email_get_env_value "$username_env")"
        password="$(email_get_env_value "$password_env")"

        [[ -n "$username" && -n "$password" ]]

        ;;

    mbox)
        local path
        local message_ids

        path="$(email_get_config "$provider" "path")"

        [[ -f "$path" ]] || return 3

        message_ids="$(
            awk '
                    /^From / {
                        in_message=1
                        next
                    }

                    in_message && /^Message-Id:/ {
                        id=$0
                        sub(/^[^:]+:[[:space:]]*/, "", id)
                        print id
                        in_message=0
                    }
                ' "$path"
        )"

        EMAIL_UIDS["$provider"]="$(printf '%s\n' "$message_ids" | sed '/^$/d')"

        EMAIL_UNREAD["$provider"]="$(printf '%s\n' "$message_ids" | sed '/^$/d' | wc -l)"

        return 0
        ;;
    maildir)
        local path
        local message_ids

        path="$(email_get_config "$provider" "path")"

        [[ -n "$path" && -d "$path" ]] || return 3
        [[ -d "$path/new" && -d "$path/cur" ]] || return 3

        message_ids="$(
            find "$path/new" "$path/cur" \
                -type f \
                -printf '%f\n' |
                sort
        )"

        EMAIL_UIDS["$provider"]="$message_ids"

        EMAIL_UNREAD["$provider"]="$(
            find "$path/new" \
                -type f \
                -printf '.' |
                wc -c
        )"
        ;;

    *)

        return 1

        ;;

    esac

}

email_collect_provider() {

    local provider="$1"

    local protocol
    local auth
    local host
    local port
    local tls
    local folder

    local username_env
    local password_env
    local username
    local password

    protocol="$(email_get_config "$provider" "protocol")"

    case "$protocol" in

    imap)

        auth="$(email_get_config "$provider" "auth")"
        host="$(email_get_config "$provider" "host")"
        port="$(email_get_config "$provider" "port")"
        tls="$(email_get_config "$provider" "tls")"
        folder="$(email_get_config "$provider" "folder")"

        [[ -n "$host" ]] || return 2

        case "$auth" in

        password)

            username_env="$(email_get_config "$provider" "username_env")"
            password_env="$(email_get_config "$provider" "password_env")"

            username="$(email_get_env_value "$username_env")"
            password="$(email_get_env_value "$password_env")"

            [[ -n "$username" && -n "$password" ]] || return 3

            ;;

        oauth2)

            # OAuth2 authentication will be implemented separately.
            return 5
            ;;

        *)

            # Unknown authentication method.
            return 6
            ;;

        esac

        port="${port:-993}"
        folder="${folder:-INBOX}"

        local url

        if [[ "$tls" == "false" ]]; then
            url="imap://${host}:${port}/${folder}"
        else
            url="imaps://${host}:${port}/${folder}"
        fi

        local result

        case "$auth" in

        password)

            result="$(
                curl \
                    --silent \
                    --show-error \
                    --fail \
                    --user "${username}:${password}" \
                    --url "$url" \
                    --request "UID SEARCH UNSEEN" \
                    2>/dev/null
            )" || return 4

            ;;

        oauth2)

            # Reserved for OAuth2 implementation.
            return 5
            ;;

        esac

        local uids

        uids="$(
            printf '%s\n' "$result" |
                grep -oE '[0-9]+' |
                tr '\n' ' ' |
                sed 's/[[:space:]]*$//'
        )"

        local count=0

        if [[ -n "$uids" ]]; then

            read -ra uid_array <<<"$uids"
            count="${#uid_array[@]}"

        fi

        EMAIL_UIDS["$provider"]="$uids"
        EMAIL_UNREAD["$provider"]="$count"

        ;;

    mbox)

        local path
        local message_ids

        path="$(email_get_config "$provider" "path")"

        [[ -n "$path" && -f "$path" ]] || return 3

        message_ids="$(
            awk '
                    /^From / {
                        in_message=1
                        next
                    }

                    in_message && /^Message-Id:/ {
                        id=$0
                        sub(/^[^:]+:[[:space:]]*/, "", id)
                        print id
                        in_message=0
                    }
                ' "$path"
        )"

        EMAIL_UIDS["$provider"]="$(printf '%s\n' "$message_ids" | sed '/^$/d')"

        EMAIL_UNREAD["$provider"]="$(
            printf '%s\n' "${EMAIL_UIDS[$provider]}" |
                sed '/^$/d' |
                wc -l
        )"

        ;;
    maildir)

        local path
        local message_ids

        path="$(email_get_config "$provider" "path")"

        [[ -n "$path" && -d "$path" ]] || return 3
        [[ -d "$path/new" && -d "$path/cur" ]] || return 3

        message_ids="$(
            find "$path/new" "$path/cur" \
                -type f \
                -printf '%f\n' |
                sort
        )"

        EMAIL_UIDS["$provider"]="$message_ids"

        EMAIL_UNREAD["$provider"]="$(
            find "$path/new" \
                -type f |
                wc -l
        )"

        ;;

    *)

        return 2
        ;;

    esac

    return 0
}

email_update_provider_state() {

    local provider="$1"

    sw_state_set \
        "provider.${provider}.uids" \
        "${EMAIL_UIDS[$provider]:-}"

    sw_state_set \
        "provider.${provider}.uids.hidden" \
        "true"

}

email_analyze() {

    EMAIL_STATUS_GLOBAL="${SW_STATUS_OK}"

    local provider
    local unread
    local new

    for provider in "${EMAIL_PROVIDERS[@]}"; do

        [[ -v "EMAIL_UNREAD[$provider]" ]] || continue

        unread="${EMAIL_UNREAD[$provider]}"
        new="${EMAIL_NEW[$provider]:-0}"

        if ((new > 0)); then
            EMAIL_STATUS["$provider"]="${SW_STATUS_INFO}"
            EMAIL_STATUS_GLOBAL="${SW_STATUS_INFO}"
        else
            EMAIL_STATUS["$provider"]="${SW_STATUS_OK}"
        fi

    done

}

email_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "$(sw_translate "Email")"
    sw_state_set "module.icon" "lucide/mail"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # Providers
    # -------------------------------------------------------------------------

    local provider
    local unread
    local new
    local detail=""

    for provider in "${EMAIL_PROVIDERS[@]}"; do

        [[ -v "EMAIL_UNREAD[$provider]" ]] || continue

        unread="${EMAIL_UNREAD[$provider]}"
        new="${EMAIL_NEW[$provider]:-0}"

        if ((new > 0)); then
            detail+="${provider}: ${unread} (${new})<br>"
        else
            detail+="${provider}: ${unread}<br>"
        fi

        #email_update_provider_state "$provider"

    done

    detail="${detail%<br>}"

    sw_state_set "count" "$(printf '%s\n' "${EMAIL_UNREAD[@]}" | awk '{s+=$1} END {print s+0}')"
    sw_state_set "count.label" "$(sw_translate "Unread")"
    sw_state_set "count.widget" "value"
    sw_state_set "count.order" "10"

    sw_state_set "details" "$detail"

}

email_report() {

    local provider

    for provider in "${EMAIL_PROVIDERS[@]}"; do

        [[ -v "EMAIL_UNREAD[$provider]" ]] || continue

        sw_log_info \
            "${MODULE_NAME}" \
            "${provider}: ${EMAIL_UNREAD[$provider]} sin leer, ${EMAIL_NEW[$provider]:-0} nuevos"

    done

}

sw_module_run() {

    sw_state_use "email"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    email_load_config

    local provider

    for provider in "${EMAIL_PROVIDERS[@]}"; do

        # A provider without both credentials is simply disabled.
        if ! email_provider_enabled "$provider"; then
            continue
        fi

        email_collect_provider "$provider" || continue

        email_load_previous "$provider"

        email_save_cache "$provider"

    done

    email_analyze

    sw_status_update "${EMAIL_STATUS_GLOBAL}" || return 1

    email_update_state

    sw_state_save

    email_report

}
