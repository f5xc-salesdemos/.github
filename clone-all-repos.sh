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
        echo "  Directory exists, pulling latest..."
        if git -C "$dir" pull --ff-only 2>&1 | sed 's/^/  /'; then
            (( refreshed++ )) || true
        else
            echo "  Warning: git pull failed for $dir"
            errors+=("$full_name (pull failed)")
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
