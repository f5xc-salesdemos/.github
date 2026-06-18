#!/usr/bin/env bash
#
# Clone (or refresh) all downstream repos from the f5xc-salesdemos organization.
# Reads the repo list from the docs-control manifest and includes docs-control and .github.
#

set -euo pipefail

MANIFEST_URL="https://raw.githubusercontent.com/f5xc-salesdemos/docs-control/refs/heads/main/.github/config/downstream-repos.json"
ORG="f5xc-salesdemos"

# --- Dependency check ---
for cmd in curl jq git; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: '$cmd' is required but not found in PATH." >&2
        exit 1
    fi
done

# --- Fetch manifest ---
echo "Fetching repo manifest..."
json=$(curl -fsSL "$MANIFEST_URL") || {
    echo "Error: failed to fetch manifest from $MANIFEST_URL" >&2
    exit 1
}

# --- Build repo list (extra repos first, then manifest entries) ---
repos=("$ORG/docs-control" "$ORG/.github")
while IFS= read -r repo; do
    repos+=("$repo")
done < <(echo "$json" | jq -r '.[]')

echo "Found ${#repos[@]} repos to process."
echo

# --- Clone or refresh each repo ---
cloned=0
refreshed=0
errors=()

for full_name in "${repos[@]}"; do
    dir="${full_name##*/}"
    echo "--- $full_name ---"

    if [ -d "$dir" ]; then
        echo "  Directory exists, refreshing..."

        # Refresh remote-tracking refs and prune branches deleted upstream.
        if ! git -C "$dir" fetch --prune origin 2>&1 | sed 's/^/  /'; then
            echo "  Warning: git fetch failed for $dir"
            errors+=("$full_name (fetch failed)")
            echo
            continue
        fi

        # Resolve the repo's default branch (origin/HEAD), repairing it if missing.
        default=$(git -C "$dir" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
        if [ -z "$default" ]; then
            git -C "$dir" remote set-head origin --auto >/dev/null 2>&1 || true
            default=$(git -C "$dir" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
        fi
        default=${default:-main}

        current=$(git -C "$dir" rev-parse --abbrev-ref HEAD)

        if [ "$current" != "$default" ]; then
            if git -C "$dir" show-ref --verify --quiet "refs/remotes/origin/$current"; then
                # Feature branch still exists upstream: fast-forward it in place.
                if git -C "$dir" merge --ff-only "origin/$current" 2>&1 | sed 's/^/  /'; then
                    echo "  On feature branch '$current' (still on remote) — left checked out."
                    (( refreshed++ )) || true
                else
                    echo "  Warning: fast-forward failed for $dir on '$current'"
                    errors+=("$full_name (ff failed on '$current')")
                fi
                echo
                continue
            fi

            # Feature branch was merged/deleted upstream. Only switch back to the
            # default branch when nothing local would be lost.
            dirty=$(git -C "$dir" status --porcelain)
            local_only=$(git -C "$dir" log --oneline "$current" --not --remotes 2>/dev/null)
            if [ -n "$dirty" ] || [ -n "$local_only" ]; then
                echo "  Skipping switch: '$current' has uncommitted changes or unpushed commits — left untouched."
                errors+=("$full_name (on '$current' with local work)")
                echo
                continue
            fi

            echo "  Branch '$current' gone upstream — switching to '$default' and removing stale branch."
            if ! git -C "$dir" checkout "$default" 2>&1 | sed 's/^/  /'; then
                echo "  Warning: failed to checkout $default for $dir"
                errors+=("$full_name (checkout failed)")
                echo
                continue
            fi
            git -C "$dir" branch -D "$current" 2>&1 | sed 's/^/  /' || true
        fi

        # Fast-forward the default branch to origin.
        if git -C "$dir" merge --ff-only "origin/$default" 2>&1 | sed 's/^/  /'; then
            (( refreshed++ )) || true
        else
            echo "  Warning: fast-forward failed for $dir on '$default' (diverged from origin)"
            errors+=("$full_name (ff failed)")
        fi
    else
        echo "  Cloning..."
        if git clone "https://github.com/${full_name}.git" 2>&1 | sed 's/^/  /'; then
            (( cloned++ )) || true
        else
            echo "  Warning: git clone failed for $full_name"
            errors+=("$full_name (clone failed)")
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
    for e in "${errors[@]}"; do
        echo "  - $e"
    done
else
    echo "Errors:    0"
fi
