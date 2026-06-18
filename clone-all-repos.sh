#!/usr/bin/env bash
#
# Clone (or refresh) all downstream repos from the f5xc-salesdemos organization.
# Reads the repo list from the docs-control manifest and includes docs-control and .github.
#

set -euo pipefail

MANIFEST_URL="https://raw.githubusercontent.com/f5xc-salesdemos/docs-control/refs/heads/main/.github/config/downstream-repos.json"
ORG="f5xc-salesdemos"

# Reason for the most recent refresh_repo/clone_repo failure (used in the summary).
REFRESH_ERR=""

# --- Dependency check ---
check_deps() {
    local cmd
    for cmd in curl jq git; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "Error: '$cmd' is required but not found in PATH." >&2
            exit 1
        fi
    done
}

# Refresh an existing repo checkout at "$1".
# Prints indented progress. On failure, sets REFRESH_ERR and returns 1.
#
# Handles the case where the local checkout is parked on a feature branch
# that was merged and deleted upstream (the naive `git pull` failure mode):
#   - default branch          -> fast-forward to origin
#   - live feature branch      -> fast-forward in place, stay checked out
#   - merged/deleted branch    -> switch back to default, delete stale branch
# The switch only runs when the branch is clean with no unpushed commits;
# otherwise the repo is left untouched and reported, so no local work is lost.
refresh_repo() {
    local dir="$1"
    REFRESH_ERR=""

    # Refresh remote-tracking refs and prune branches deleted upstream.
    if ! git -C "$dir" fetch --prune origin 2>&1 | sed 's/^/  /'; then
        echo "  Warning: git fetch failed for $dir"
        REFRESH_ERR="fetch failed"
        return 1
    fi

    # Resolve the repo's default branch (origin/HEAD), repairing it if missing.
    local default
    default=$(git -C "$dir" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    if [ -z "$default" ]; then
        git -C "$dir" remote set-head origin --auto >/dev/null 2>&1 || true
        default=$(git -C "$dir" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    fi
    default=${default:-main}

    local current
    current=$(git -C "$dir" rev-parse --abbrev-ref HEAD)

    if [ "$current" != "$default" ]; then
        if git -C "$dir" show-ref --verify --quiet "refs/remotes/origin/$current"; then
            # Feature branch still exists upstream: fast-forward it in place.
            if git -C "$dir" merge --ff-only "origin/$current" 2>&1 | sed 's/^/  /'; then
                echo "  On feature branch '$current' (still on remote) — left checked out."
                return 0
            fi
            echo "  Warning: fast-forward failed for $dir on '$current'"
            REFRESH_ERR="ff failed on '$current'"
            return 1
        fi

        # Feature branch was merged/deleted upstream. Only switch back to the
        # default branch when nothing local would be lost.
        local dirty local_only
        dirty=$(git -C "$dir" status --porcelain)
        local_only=$(git -C "$dir" log --oneline "$current" --not --remotes 2>/dev/null)
        if [ -n "$dirty" ] || [ -n "$local_only" ]; then
            echo "  Skipping switch: '$current' has uncommitted changes or unpushed commits — left untouched."
            REFRESH_ERR="on '$current' with local work"
            return 1
        fi

        echo "  Branch '$current' gone upstream — switching to '$default' and removing stale branch."
        if ! git -C "$dir" checkout "$default" 2>&1 | sed 's/^/  /'; then
            echo "  Warning: failed to checkout $default for $dir"
            REFRESH_ERR="checkout failed"
            return 1
        fi
        git -C "$dir" branch -D "$current" 2>&1 | sed 's/^/  /' || true
    fi

    # Fast-forward the default branch to origin.
    if git -C "$dir" merge --ff-only "origin/$default" 2>&1 | sed 's/^/  /'; then
        return 0
    fi
    echo "  Warning: fast-forward failed for $dir on '$default' (diverged from origin)"
    REFRESH_ERR="ff failed"
    return 1
}

# Clone "$1" (org/name) into the current directory.
# On failure, sets REFRESH_ERR and returns 1.
clone_repo() {
    local full_name="$1"
    REFRESH_ERR=""
    if git clone "https://github.com/${full_name}.git" 2>&1 | sed 's/^/  /'; then
        return 0
    fi
    echo "  Warning: git clone failed for $full_name"
    REFRESH_ERR="clone failed"
    return 1
}

main() {
    check_deps

    # --- Fetch manifest ---
    echo "Fetching repo manifest..."
    local json
    json=$(curl -fsSL "$MANIFEST_URL") || {
        echo "Error: failed to fetch manifest from $MANIFEST_URL" >&2
        exit 1
    }

    # --- Build repo list (extra repos first, then manifest entries) ---
    local repos=("$ORG/docs-control" "$ORG/.github")
    local repo
    while IFS= read -r repo; do
        repos+=("$repo")
    done < <(echo "$json" | jq -r '.[]')

    echo "Found ${#repos[@]} repos to process."
    echo

    # --- Clone or refresh each repo ---
    local cloned=0 refreshed=0
    local errors=()
    local full_name dir

    for full_name in "${repos[@]}"; do
        dir="${full_name##*/}"
        echo "--- $full_name ---"

        if [ -d "$dir" ]; then
            echo "  Directory exists, refreshing..."
            if refresh_repo "$dir"; then
                (( refreshed++ )) || true
            else
                errors+=("$full_name ($REFRESH_ERR)")
            fi
        else
            echo "  Cloning..."
            if clone_repo "$full_name"; then
                (( cloned++ )) || true
            else
                errors+=("$full_name ($REFRESH_ERR)")
            fi
        fi
        echo
    done

    # --- Summary ---
    echo "===== Summary ====="
    echo "Cloned:    $cloned"
    echo "Refreshed: $refreshed"
    if [ ${#errors[@]} -gt 0 ]; then
        echo "Errors:    ${#errors[@]}"
        local e
        for e in "${errors[@]}"; do
            echo "  - $e"
        done
    else
        echo "Errors:    0"
    fi
}

# Only run when executed directly, so the functions can be sourced for testing.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
