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

    echo "$response" | jq . > "/home/daniel/scripts/syswatch/cache/github.json"

    GIT_GITHUB_REPOS=$(
        printf '%s\n' "$response" |
            jq 'length'
    ) || return 1

    GIT_GITHUB_ISSUES=$(
    printf '%s\n' "$response" |
        jq '[.[].open_issues_count // 0] | add'
    ) || return 1

    GIT_GITHUB_FORKS=$(
    printf '%s\n' "$response" |
        jq '[.[].forks_count // 0] | add'
    ) || return 1

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

    echo "$response" |
        jq . > "/home/daniel/scripts/syswatch/cache/gitea.json"

    GIT_GITEA_REPOS=$(
        printf '%s\n' "$response" |
            jq 'length'
    ) || return 1

    GIT_GITEA_ISSUES=$(
        printf '%s\n' "$response" |
            jq '[.[].open_issues_count // 0] | add'
    ) || return 1

    GIT_GITEA_PR=$(
        printf '%s\n' "$response" |
            jq '[.[].open_pr_counter // 0] | add'
    ) || return 1

    GIT_GITEA_FORKS=$(
        printf '%s\n' "$response" |
            jq '[.[].forks_count // 0] | add'
    ) || return 1

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

    echo "$response" |
        jq . > "/home/daniel/scripts/syswatch/cache/codeberg.json"

    GIT_CODEBERG_REPOS=$(
        printf '%s\n' "$response" |
            jq 'length'
    ) || return 1

    GIT_CODEBERG_ISSUES=$(
        printf '%s\n' "$response" |
            jq '[.[].open_issues_count // 0] | add'
    ) || return 1

    GIT_CODEBERG_PR=$(
        printf '%s\n' "$response" |
            jq '[.[].open_pr_counter // 0] | add'
    ) || return 1

    GIT_CODEBERG_FORKS=$(
        printf '%s\n' "$response" |
            jq '[.[].forks_count // 0] | add'
    ) || return 1

}



git_collect() {

    local failed=0

    GIT_GITHUB_REPOS=0
    GIT_CODEBERG_REPOS=0
    GIT_GITEA_REPOS=0

    GIT_GITHUB_ISSUES=0
    GIT_GITHUB_FORKS=0
    GIT_GITHUB_PREVIOUS_ISSUES=0
    GIT_GITHUB_PREVIOUS_FORKS=0

    GIT_CODEBERG_ISSUES=0
    GIT_CODEBERG_FORKS=0
    GIT_CODEBERG_PR=0
    GIT_CODEBERG_PREVIOUS_ISSUES=0
    GIT_CODEBERG_PREVIOUS_FORKS=0
    GIT_CODEBERG_PREVIOUS_PR=0

    GIT_GITEA_ISSUES=0
    GIT_GITEA_FORKS=0
    GIT_GITEA_PR=0
    GIT_GITEA_PREVIOUS_ISSUES=0
    GIT_GITEA_PREVIOUS_FORKS=0
    GIT_GITEA_PREVIOUS_PR=0

    

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

git_check_increase() {

    local metric="$1"
    local current="$2"
    local file
    local previous

    TEMP_VALUE=0

    file="${PROJECT_DIR}/csv/git/${metric}.csv"

    [[ ! -f "$file" ]] && return 0

    previous=$(
        tail -n 1 "$file" |
            cut -d',' -f2
    )

    [[ -z "$previous" ]] && return 0

    TEMP_VALUE=$previous

    if (( current > previous )); then
        return 1
    fi

    return 0
}


git_analyze() {

    GIT_STATUS="${SW_STATUS_OK}"

    TEMP_VALUE=0

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


    # -------------------------------------------------------------------------
    # Activity increase
    # -------------------------------------------------------------------------

    if [[ -n "$GITHUB_HOST" ]]; then

        if ! git_check_increase \
            "github_issues" \
            "$GIT_GITHUB_ISSUES"; then

            GIT_STATUS="${SW_STATUS_INFO}"

            GIT_GITHUB_PREVIOUS_ISSUES=$TEMP_VALUE

        fi

        if ! git_check_increase \
            "github_forks" \
            "$GIT_GITHUB_FORKS"; then

            GIT_STATUS="${SW_STATUS_INFO}"

            GIT_GITHUB_PREVIOUS_FORKS=$TEMP_VALUE

        fi

    fi

    if [[ -n "$CODEBERG_HOST" ]]; then

        if ! git_check_increase \
            "codeberg_issues" \
            "$GIT_CODEBERG_ISSUES"; then

            GIT_STATUS="${SW_STATUS_INFO}"

            GIT_CODEBERG_PREVIOUS_ISSUES=$TEMP_VALUE

        fi

        if ! git_check_increase \
            "codeberg_forks" \
            "$GIT_CODEBERG_FORKS"; then

            GIT_STATUS="${SW_STATUS_INFO}"

            GIT_CODEBERG_PREVIOUS_FORKS=$TEMP_VALUE

        fi

        if ! git_check_increase \
            "codeberg_pr" \
            "$GIT_CODEBERG_PR"; then

            GIT_STATUS="${SW_STATUS_INFO}"

            GIT_CODEBERG_PREVIOUS_PR=$TEMP_VALUE

        fi

    fi

    if [[ -n "$GITEA_HOST" ]]; then

        if ! git_check_increase \
            "gitea_issues" \
            "$GIT_GITEA_ISSUES"; then

            GIT_STATUS="${SW_STATUS_INFO}"

            GIT_GITEA_PREVIOUS_ISSUES=$TEMP_VALUE

        fi

        if ! git_check_increase \
            "gitea_forks" \
            "$GIT_GITEA_FORKS"; then

            GIT_STATUS="${SW_STATUS_INFO}"

            GIT_GITEA_PREVIOUS_FORKS=$TEMP_VALUE

        fi

        if ! git_check_increase \
            "gitea_pr" \
            "$GIT_GITEA_PR"; then

            GIT_STATUS="${SW_STATUS_INFO}"

            GIT_GITEA_PREVIOUS_PR=$TEMP_VALUE

        fi

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

        local github_issues_unit="$(sw_translate "open")"
        local github_forks_unit="$(sw_translate "created")"

        if (( GIT_GITHUB_PREVIOUS_ISSUES > 0 )); then
            github_issues_unit+=" ($GIT_GITHUB_PREVIOUS_ISSUES)"
        fi

        if (( GIT_GITHUB_PREVIOUS_FORKS > 0 )); then
            github_forks_unit+=" ($GIT_GITHUB_PREVIOUS_FORKS)"
        fi

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

        sw_state_set \
            "github_issues" \
            "${GIT_GITHUB_ISSUES}"

        sw_state_set \
            "github_issues.label" \
            "$(sw_translate "↳ Issues")"

        sw_state_set \
            "github_issues.widget" \
            "value"

        sw_state_set \
            "github_issues.unit" \
            "$github_issues_unit"

        sw_state_set \
            "github_issues.order" \
            "11"

        sw_state_set \
            "github_forks" \
            "${GIT_GITHUB_FORKS}"

        sw_state_set \
            "github_forks.label" \
            "$(sw_translate "↳ Forks")"

        sw_state_set \
            "github_forks.widget" \
            "value"

        sw_state_set \
            "github_forks.unit" \
            "$github_forks_unit"

        sw_state_set \
            "github_forks.order" \
            "12"    

    fi

    # -------------------------------------------------------------------------
    # Codeberg
    # -------------------------------------------------------------------------

    if [[ -n "$CODEBERG_HOST" ]]; then

        local github_issues_unit="$(sw_translate "open")"
        local github_forks_unit="$(sw_translate "created")"
        local github_pr_unit="$(sw_translate "created")"

        if (( GIT_CODEBERG_PREVIOUS_ISSUES > 0 )); then
            github_issues_unit+=" ($GIT_CODEBERG_PREVIOUS_ISSUES)"
        fi

        if (( GIT_CODEBERG_PREVIOUS_FORKS > 0 )); then
            github_forks_unit+=" ($GIT_CODEBERG_PREVIOUS_FORKS)"
        fi

        if (( GIT_CODEBERG_PREVIOUS_PR > 0 )); then
            github_pr_unit+=" ($GIT_CODEBERG_PREVIOUS_PR)"
        fi



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

        sw_state_set \
            "codeberg_issues" \
            "${GIT_CODEBERG_ISSUES}"

        sw_state_set \
            "codeberg_issues.label" \
            "$(sw_translate "↳ Issues")"

        sw_state_set \
            "codeberg_issues.widget" \
            "value"

        sw_state_set \
            "codeberg_issues.unit" \
            "$github_issues_unit"

        sw_state_set \
            "codeberg_issues.order" \
            "21"

        sw_state_set \
            "codeberg_forks" \
            "${GIT_CODEBERG_FORKS}"

        sw_state_set \
            "codeberg_forks.label" \
            "$(sw_translate "↳ Forks")"

        sw_state_set \
            "codeberg_forks.widget" \
            "value"

        sw_state_set \
            "codeberg_forks.unit" \
            "$github_forks_unit"

        sw_state_set \
            "codeberg_forks.order" \
            "22"        

        sw_state_set \
            "codeberg_pr" \
            "${GIT_CODEBERG_PR}"

        sw_state_set \
            "codeberg_pr.label" \
            "$(sw_translate "↳ Pull requests")"

        sw_state_set \
            "codeberg_pr.widget" \
            "value"

        sw_state_set \
            "codeberg_pr.unit" \
            "$github_forks_unit"

        sw_state_set \
            "codeberg_pr.order" \
            "23"        
    

    fi

    # -------------------------------------------------------------------------
    # Gitea
    # -------------------------------------------------------------------------

    if [[ -n "$GITEA_HOST" ]]; then

        local github_issues_unit="$(sw_translate "open")"
        local github_forks_unit="$(sw_translate "created")"
        local github_pr_unit="$(sw_translate "created")"

        if (( GIT_GITEA_PREVIOUS_ISSUES > 0 )); then
            github_issues_unit+=" ($GIT_GITEA_PREVIOUS_ISSUES)"
        fi

        if (( GIT_GITEA_PREVIOUS_FORKS > 0 )); then
            github_forks_unit+=" ($GIT_GITEA_PREVIOUS_FORKS)"
        fi

        if (( GIT_GITEA_PREVIOUS_PR > 0 )); then
            github_pr_unit+=" ($GIT_GITEA_PREVIOUS_PR)"
        fi



        sw_state_set \
            "gitea" \
            "${GIT_GITEA_REPOS}"

        sw_state_set \
            "gitea.label" \
            "Gitea/Forgejo"

        sw_state_set \
            "gitea.widget" \
            "value"

        sw_state_set \
            "gitea.unit" \
            "repos"

        sw_state_set \
            "gitea.order" \
            "30"

        sw_state_set \
            "gitea_issues" \
            "${GIT_GITEA_ISSUES}"

        sw_state_set \
            "gitea_issues.label" \
            "$(sw_translate "↳ Issues")"

        sw_state_set \
            "gitea_issues.widget" \
            "value"

        sw_state_set \
            "gitea_issues.unit" \
            "$github_issues_unit"

        sw_state_set \
            "gitea_issues.order" \
            "31"

        sw_state_set \
            "gitea_forks" \
            "${GIT_GITEA_FORKS}"

        sw_state_set \
            "gitea_forks.label" \
            "$(sw_translate "↳ Forks")"

        sw_state_set \
            "gitea_forks.widget" \
            "value"

        sw_state_set \
            "gitea_forks.unit" \
            "$github_forks_unit"

        sw_state_set \
            "gitea_forks.order" \
            "32"        

        sw_state_set \
            "gitea_pr" \
            "${GIT_GITEA_PR}"

        sw_state_set \
            "gitea_pr.label" \
            "$(sw_translate "↳ Pull requests")"

        sw_state_set \
            "gitea_pr.widget" \
            "value"

        sw_state_set \
            "gitea_pr.unit" \
            "$github_forks_unit"

        sw_state_set \
            "gitea_pr.order" \
            "33"        
    

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

    sw_csv_append "git" "github_issues" "$GIT_GITHUB_ISSUES"
    sw_csv_append "git" "github_forks" "$GIT_GITHUB_FORKS"

    sw_csv_append "git" "codeberg_issues" "$GIT_CODEBERG_ISSUES"
    sw_csv_append "git" "codeberg_forks" "$GIT_CODEBERG_FORKS"
    sw_csv_append "git" "codeberg_pr" "$GIT_CODEBERG_PR"

    sw_csv_append "git" "gitea_issues" "$GIT_GITEA_ISSUES"
    sw_csv_append "git" "gitea_forks" "$GIT_GITEA_FORKS"
    sw_csv_append "git" "gitea_pr" "$GIT_GITEA_PR"


    git_report

}