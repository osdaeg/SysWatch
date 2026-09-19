#!/usr/bin/env bash
#
# -----------------------------------------------------------------------------
# SysWatch
#
# git module
#
# Copyright (c) 2026 Daniel Eguren
# Licensed under the MIT License.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Module metadata
# -----------------------------------------------------------------------------

readonly MODULE_NAME="Git"
readonly MODULE_DESCRIPTION="Git repository summary"
readonly MODULE_VERSION="0.1.0"
MODULE_INTERVAL=${MODULE_INTERVAL:-300}
MODULE_ORDER=${MODULE_ORDER:-10}
MODULE_REMOTE=${MODULE_REMOTE:-""}


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

readonly GITHUB_USER="${GITHUB_USER:-}"
readonly GITHUB_HOST="${GITHUB_HOST:-}"
readonly GITHUB_TOKEN="${GITHUB_TOKEN:-}"

readonly CODEBERG_USER="${CODEBERG_USER:-}"
readonly CODEBERG_HOST="${CODEBERG_HOST:-}"
readonly CODEBERG_TOKEN="${CODEBERG_TOKEN:-}"

readonly GITEA_USER="${GITEA_USER:-}"
readonly GITEA_HOST="${GITEA_HOST:-}"
readonly GITEA_TOKEN="${GITEA_TOKEN:-}"


# -----------------------------------------------------------------------------
# Module variables
# -----------------------------------------------------------------------------

GIT_GITHUB_REPOS=0
GIT_CODEBERG_REPOS=0
GIT_GITEA_REPOS=0

GIT_STATUS="${SW_STATUS_UNKNOWN}"


# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

git_github() {

    local response

    if [[ -z "$GITHUB_HOST" ]]; then
        return 0
    fi

    if [[ -z "$GITHUB_TOKEN" ]]; then
        return 1
    fi

    response=$(
    curl -fsS \
        --max-time 10 \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.${GITHUB_HOST}/user/repos?per_page=100&page=1"
    ) || return 1

    GIT_GITHUB_REPOS=$(
    printf '%s\n' "$response" |
        jq 'length'
    )

}


git_codeberg() {

    local response

    if [[ -z "$CODEBERG_HOST" ]]; then
        return 0
    fi

    if [[ -z "$CODEBERG_TOKEN" ]]; then
        return 1
    fi

    response=$(
        curl -fsS \
            --max-time 10 \
            -H "Authorization: token ${CODEBERG_TOKEN}" \
            "https://${CODEBERG_HOST}/api/v1/user/repos?limit=50&page=1"
    ) || return 1

    GIT_CODEBERG_REPOS=$(
    printf '%s\n' "$response" |
        jq 'length'
    )

}


git_gitea() {

    local response

    if [[ -z "$GITEA_HOST" ]]; then
        return 0
    fi

    if [[ -z "$GITEA_TOKEN" ]]; then
        return 1
    fi

    response=$(
        curl -fsS \
            --max-time 10 \
            -H "Authorization: token ${GITEA_TOKEN}" \
            "http://${GITEA_HOST}/api/v1/user/repos?limit=50&page=1"
    ) || return 1

    GIT_GITEA_REPOS=$(
    printf '%s\n' "$response" |
        jq 'length'
    )

}


git_collect() {

    local failed=0

    GIT_GITHUB_REPOS=0
    GIT_CODEBERG_REPOS=0
    GIT_GITEA_REPOS=0

    if [[ -n "$GITHUB_HOST" ]]; then
        git_github || failed=1
    fi

    if [[ -n "$CODEBERG_HOST" ]]; then
        git_codeberg || failed=1
    fi

    if [[ -n "$GITEA_HOST" ]]; then
        git_gitea || failed=1
    fi

    return "$failed"

}


git_analyze() {

    GIT_STATUS="${SW_STATUS_OK}"

    if [[ -n "$GITHUB_HOST" && -z "$GITHUB_TOKEN" ]]; then
        GIT_STATUS="${SW_STATUS_UNKNOWN}"
        return
    fi

    if [[ -n "$CODEBERG_HOST" && -z "$CODEBERG_TOKEN" ]]; then
        GIT_STATUS="${SW_STATUS_UNKNOWN}"
        return
    fi

    if [[ -n "$GITEA_HOST" && -z "$GITEA_TOKEN" ]]; then
        GIT_STATUS="${SW_STATUS_UNKNOWN}"
        return
    fi

}


git_update_state() {

    sw_state_set "module_version" "${MODULE_VERSION}"

    # -------------------------------------------------------------------------
    # Module metadata
    # -------------------------------------------------------------------------

    sw_state_set "module.label" "Git"
    sw_state_set "module.icon" "lucide/git-branch"
    sw_state_set "module.order" "$MODULE_ORDER"

    # -------------------------------------------------------------------------
    # GitHub
    # -------------------------------------------------------------------------

    if [[ -n "$GITHUB_HOST" ]]; then

        sw_state_set \
            "github" \
            "${GIT_GITHUB_REPOS}"

        sw_state_set \
            "github.label" \
            "GitHub"

        sw_state_set \
            "github.widget" \
            "value"

        sw_state_set \
            "github.unit" \
            "repos"

        sw_state_set \
            "github.order" \
            "10"

    fi

    # -------------------------------------------------------------------------
    # Codeberg
    # -------------------------------------------------------------------------

    if [[ -n "$CODEBERG_HOST" ]]; then

        sw_state_set \
            "codeberg" \
            "${GIT_CODEBERG_REPOS}"

        sw_state_set \
            "codeberg.label" \
            "Codeberg"

        sw_state_set \
            "codeberg.widget" \
            "value"

        sw_state_set \
            "codeberg.unit" \
            "repos"

        sw_state_set \
            "codeberg.order" \
            "20"

    fi

    # -------------------------------------------------------------------------
    # Gitea
    # -------------------------------------------------------------------------

    if [[ -n "$GITEA_HOST" ]]; then

        sw_state_set \
            "gitea" \
            "${GIT_GITEA_REPOS}"

        sw_state_set \
            "gitea.label" \
            "Gitea"

        sw_state_set \
            "gitea.widget" \
            "value"

        sw_state_set \
            "gitea.unit" \
            "repos"

        sw_state_set \
            "gitea.order" \
            "30"

    fi

}


git_report() {

    local message=""

    [[ -n "$GITHUB_HOST" ]] &&
        message+="GitHub: ${GIT_GITHUB_REPOS} repositorios. "

    [[ -n "$CODEBERG_HOST" ]] &&
        message+="Codeberg: ${GIT_CODEBERG_REPOS} repositorios. "

    [[ -n "$GITEA_HOST" ]] &&
        message+="Gitea: ${GIT_GITEA_REPOS} repositorios."

    sw_log_info \
        "${MODULE_NAME}" \
        "${message}"

}


sw_module_run() {

    sw_state_use "git"

    if [[ -n "$MODULE_REMOTE" ]]; then
        sw_state_remote "$MODULE_REMOTE"
    fi

    sw_state_load

    git_collect

    git_analyze

    sw_status_update "${GIT_STATUS}" || return 1

    git_update_state

    sw_state_save

    git_report

}