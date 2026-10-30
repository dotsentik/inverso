#!/bin/bash
# Fails if a published GitHub security advisory of Sparkle affects the version pinned in
# Package.resolved. Dependabot does not see that file (it lies inside the Xcode project),
# so its alerts never cover Sparkle; .github/workflows/sparkle-advisories.yml runs this
# on a schedule instead.
#
# An advisory affects the pinned version when that version is below one of the advisory's
# patched versions and not below the lower bound of its vulnerable range (">= x" if given).
#
# Usage: scripts/check-sparkle-advisories.sh   (needs gh, authenticated or GH_TOKEN)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOLVED="$REPO_ROOT/Inverso.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

PINNED="$(jq -r '.pins[] | select(.identity == "sparkle") | .state.version' "$RESOLVED")"
[[ "$PINNED" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "error: no Sparkle version in $RESOLVED" >&2; exit 2; }
echo "Pinned Sparkle: $PINNED"

# version_lt a b: true if a < b
version_lt() {
    [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$1" ]]
}

AFFECTED=0
while IFS=$'\t' read -r id range patched; do
    lower="$(sed -n 's/.*>= *\([0-9][0-9.]*\).*/\1/p' <<<"$range")"
    for fix in ${patched//,/ }; do
        if version_lt "$PINNED" "$fix" && { [[ -z "$lower" ]] || ! version_lt "$PINNED" "$lower"; }; then
            echo "AFFECTED  $id  vulnerable: $range  patched: $patched"
            AFFECTED=1
            break
        fi
    done
done < <(gh api --paginate "repos/sparkle-project/Sparkle/security-advisories?state=published" \
    --jq '.[] | .ghsa_id as $id | .vulnerabilities[] | [$id, .vulnerable_version_range, (.patched_versions // "")] | @tsv')

if [[ "$AFFECTED" == 1 ]]; then
    echo "Update Sparkle (Package.resolved) and publish a release." >&2
    exit 1
fi
echo "No published advisory affects Sparkle $PINNED"
