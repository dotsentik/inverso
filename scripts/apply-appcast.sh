#!/bin/bash
# Publishes the feed entry prepared by scripts/release.sh: copies dist/appcast.xml to
# appcast.xml in the repository root. Run it only after the zip is attached to the GitHub
# Release; then commit appcast.xml on its own ("Publish appcast for v<version>") and push.
#
# Copies nothing unless:
#   - dist/appcast.xml is valid XML with exactly one <item>;
#   - its enclosure URL is .../releases/download/v<version>/Inverso-<version>.zip;
#   - its length equals the size of dist/Inverso-<version>.zip;
#   - the EdDSA signature of that zip is valid for SUPublicEDKey (and sign_update --verify
#     accepts it, if Sparkle's tools are built);
#   - its sparkle:version equals CFBundleVersion of dist/Inverso.app and is greater
#     than the build of the previous release in the current appcast.xml;
#   - the zip is downloadable from the GitHub Release (HTTP 200, anonymously).
#
# Usage: scripts/apply-appcast.sh

set -euo pipefail
unset GH_TOKEN GITHUB_TOKEN

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

APPCAST="appcast.xml"
DIST="dist"
DIST_APPCAST="$DIST/appcast.xml"
PLIST="Inverso/Info.plist"
SPARKLE_BIN="build/dist-derived/SourcePackages/artifacts/sparkle/Sparkle/bin"
DOWNLOAD_BASE="https://github.com/dotsentik/inverso/releases/download"

fail() {
    echo "error: $*" >&2
    exit 1
}

xpath() {
    xmllint --xpath "$1" "$2" 2>/dev/null || true
}

[[ -f "$DIST_APPCAST" ]] || fail "$DIST_APPCAST not found, run scripts/release.sh first"
xmllint --noout "$DIST_APPCAST" || fail "$DIST_APPCAST is not valid XML"
ITEMS="$(xpath 'count(//item)' "$DIST_APPCAST")"
[[ "$ITEMS" == 1 ]] || fail "$DIST_APPCAST must have exactly one <item>, has $ITEMS"

VERSION="$(xpath "string(//item/*[local-name()='shortVersionString'])" "$DIST_APPCAST")"
BUILD="$(xpath "string(//item/*[local-name()='version'])" "$DIST_APPCAST")"
URL="$(xpath 'string(//item/enclosure/@url)' "$DIST_APPCAST")"
LENGTH="$(xpath 'string(//item/enclosure/@length)' "$DIST_APPCAST")"
SIGNATURE="$(xpath "string(//item/enclosure/@*[local-name()='edSignature'])" "$DIST_APPCAST")"
[[ -n "$VERSION" && "$BUILD" =~ ^[0-9]+$ && -n "$SIGNATURE" ]] ||
    fail "the item lacks sparkle:shortVersionString, a numeric sparkle:version or sparkle:edSignature"
echo "Item: $VERSION (build $BUILD)"

ZIP="$DIST/Inverso-$VERSION.zip"
EXPECTED_URL="$DOWNLOAD_BASE/v$VERSION/Inverso-$VERSION.zip"
[[ "$URL" == "$EXPECTED_URL" ]] || fail "enclosure URL is $URL, expected $EXPECTED_URL"
echo "Enclosure URL: OK"

[[ -f "$ZIP" ]] || fail "$ZIP not found"
SIZE="$(stat -f %z "$ZIP")"
[[ "$LENGTH" == "$SIZE" ]] || fail "length=$LENGTH, but $ZIP has $SIZE bytes"
echo "Length: OK ($SIZE bytes)"

PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST")" || fail "SUPublicEDKey is missing from $PLIST"
xcrun swift scripts/verify-ed-signature.swift "$PUBLIC_KEY" "$SIGNATURE" "$ZIP" ||
    fail "the signature of $ZIP is not valid for SUPublicEDKey"
if [[ -x "$SPARKLE_BIN/sign_update" && -x "$SPARKLE_BIN/generate_keys" ]]; then
    [[ "$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null)" == "$PUBLIC_KEY" ]] ||
        fail "the Keychain signing key does not belong to SUPublicEDKey"
    "$SPARKLE_BIN/sign_update" --verify "$ZIP" "$SIGNATURE" >/dev/null || fail "sign_update --verify rejected $ZIP"
    echo "Signature: OK (SUPublicEDKey, sign_update --verify)"
else
    echo "Signature: OK (SUPublicEDKey; sign_update not built, skipped)"
fi

APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DIST/Inverso.app/Contents/Info.plist")" ||
    fail "$DIST/Inverso.app not found"
[[ "$BUILD" == "$APP_BUILD" ]] || fail "sparkle:version is $BUILD, CFBundleVersion of the built app is $APP_BUILD"
PREVIOUS="$(sed -n 's/.*<sparkle:version>\([0-9]*\)<\/sparkle:version>.*/\1/p' "$APPCAST" 2>/dev/null | sort -n | tail -1)"
PREVIOUS="${PREVIOUS:-0}"
[[ "$BUILD" -gt "$PREVIOUS" ]] || fail "build $BUILD is not greater than the published build $PREVIOUS"
echo "Version: OK (build $BUILD > published $PREVIOUS, matches the app)"

STATUS="$(curl -sIL --netrc-file /dev/null -o /dev/null -w '%{http_code}' "$URL" || true)"
[[ "$STATUS" == 200 ]] ||
    fail "the zip is not downloadable yet (HTTP $STATUS): create the GitHub Release first; the repository must be public"
echo "GitHub Release zip: OK (HTTP 200)"

cp "$DIST_APPCAST" "$APPCAST"
echo
echo "Copied $DIST_APPCAST to $APPCAST. Next:"
echo "  git add $APPCAST && git commit -m \"Publish appcast for v$VERSION\" && git push origin main"
echo "  scripts/check-feed.sh --installed-build $PREVIOUS   (after up to 5 minutes)"
