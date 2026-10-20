#!/bin/bash
# Checks the published update feed the way installed copies see it: anonymously, without
# tokens or logins. Run it after publishing a release (see CONTRIBUTING.md, Releasing).
#
# Usage: scripts/check-feed.sh [feed URL] [--installed-build <build>]
#   feed URL          default: SUFeedURL from Inverso/Info.plist
#   --installed-build the CFBundleVersion of an installed copy: the newest sparkle:version
#                     in the feed must be greater, or that copy is offered no update
#
# Checks, each reported as PASS or FAIL at the end:
#   - the feed answers HTTP 200 and is valid XML;
#   - every enclosure URL answers HTTP 200 (curl -sIL, redirects followed), its
#     Content-Length and the size of the downloaded zip equal the length attribute;
#   - the EdDSA signature of every zip is valid for SUPublicEDKey from Info.plist (and
#     sign_update --verify accepts it, if Sparkle's tools are built);
#   - with --installed-build: the newest sparkle:version is greater than that build.
# A feed that differs from appcast.xml in the working copy is reported: the file may not
# be pushed yet, or raw.githubusercontent.com still serves a cached copy (up to ~5 minutes).
#
# Exits with 1 if any check fails.

set -uo pipefail
unset GH_TOKEN GITHUB_TOKEN

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PLIST="Inverso/Info.plist"
SPARKLE_BIN="build/dist-derived/SourcePackages/artifacts/sparkle/Sparkle/bin"

usage() {
    echo "usage: $0 [feed URL] [--installed-build <build>]" >&2
    exit 2
}

FEED_URL=""
INSTALLED_BUILD=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --installed-build)
            [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || usage
            INSTALLED_BUILD="$2"
            shift 2
            ;;
        -*) usage ;;
        *)
            [[ -z "$FEED_URL" ]] || usage
            FEED_URL="$1"
            shift
            ;;
    esac
done
FEED_URL="${FEED_URL:-$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$PLIST")}"
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$PLIST")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

RESULTS=()
FAILED=0

pass() {
    RESULTS+=("PASS  $*")
    echo "PASS  $*"
}

fail() {
    RESULTS+=("FAIL  $*")
    echo "FAIL  $*"
    FAILED=1
}

note() {
    echo "      $*"
}

# Prints the summary and exits: 1 if any check failed.
finish() {
    echo
    echo "==> Summary for $FEED_URL"
    printf '%s\n' "${RESULTS[@]}"
    if [[ "$FAILED" == 1 ]]; then
        echo "Result: FAIL"
        exit 1
    fi
    echo "Result: PASS"
    exit 0
}

explain_404() {
    note "404: the repository is private or the file is not published yet"
    note "(raw.githubusercontent.com may also serve a cached copy for up to ~5 minutes)"
}

xpath() {
    xmllint --xpath "$1" "$2" 2>/dev/null || true
}

echo "Feed: $FEED_URL"
[[ -n "$INSTALLED_BUILD" ]] && echo "Installed build: $INSTALLED_BUILD"
echo

# --- Feed --------------------------------------------------------------------

FEED="$WORK/appcast.xml"
# -f fails on HTTP errors; -w still reports the status. No netrc, no auth headers.
STATUS="$(curl -fsSL --netrc-file /dev/null -o "$FEED" -w '%{http_code}' "$FEED_URL" 2>/dev/null || true)"
if [[ "$STATUS" == 200 ]]; then
    pass "feed: HTTP 200"
else
    fail "feed: HTTP ${STATUS:-000}"
    [[ "$STATUS" == 404 ]] && explain_404
    finish
fi

if xmllint --noout "$FEED" 2>/dev/null; then
    pass "feed: valid XML"
else
    fail "feed: not valid XML"
    finish
fi

if [[ -f appcast.xml ]] && ! cmp -s "$FEED" appcast.xml; then
    note "the published feed differs from appcast.xml in the working copy: not pushed yet, or"
    note "raw.githubusercontent.com still serves a cached copy (up to ~5 minutes); retry later"
fi

ITEMS="$(xpath 'count(//item)' "$FEED")"
ITEMS="${ITEMS:-0}"
note "$ITEMS item(s)"
[[ "$ITEMS" -gt 0 ]] || note "no <item>: installed copies are told there are no updates"

# --- Enclosures --------------------------------------------------------------

NEWEST=0
for ((i = 1; i <= ITEMS; i++)); do
    ITEM="//item[$i]"
    BUILD="$(xpath "string($ITEM/*[local-name()='version'])" "$FEED")"
    VERSION="$(xpath "string($ITEM/*[local-name()='shortVersionString'])" "$FEED")"
    URL="$(xpath "string($ITEM/enclosure/@url)" "$FEED")"
    LENGTH="$(xpath "string($ITEM/enclosure/@length)" "$FEED")"
    SIGNATURE="$(xpath "string($ITEM/enclosure/@*[local-name()='edSignature'])" "$FEED")"
    LABEL="$VERSION (build $BUILD)"
    [[ "$BUILD" =~ ^[0-9]+$ && "$BUILD" -gt "$NEWEST" ]] && NEWEST="$BUILD"

    if [[ -z "$URL" || -z "$LENGTH" || -z "$SIGNATURE" ]]; then
        fail "$LABEL: enclosure lacks url, length or sparkle:edSignature"
        continue
    fi

    HEADERS="$(curl -sIL --netrc-file /dev/null "$URL" 2>/dev/null || true)"
    STATUS="$(tr -d '\r' <<<"$HEADERS" | awk '/^HTTP\// { code = $2 } END { print code }')"
    if [[ "$STATUS" != 200 ]]; then
        fail "$LABEL: enclosure HTTP ${STATUS:-000} ($URL)"
        [[ "$STATUS" == 404 ]] && explain_404
        continue
    fi
    pass "$LABEL: enclosure HTTP 200"

    # Content-Length of the final response, after redirects
    CONTENT_LENGTH="$(tr -d '\r' <<<"$HEADERS" | awk 'tolower($1) == "content-length:" { value = $2 } END { print value }')"
    if [[ -n "$CONTENT_LENGTH" && "$CONTENT_LENGTH" != "$LENGTH" ]]; then
        fail "$LABEL: Content-Length $CONTENT_LENGTH, length=$LENGTH"
    fi

    ZIP="$WORK/update-$i.zip"
    if ! curl -fsSL --netrc-file /dev/null -o "$ZIP" "$URL" 2>/dev/null; then
        fail "$LABEL: download failed"
        continue
    fi
    SIZE="$(stat -f %z "$ZIP")"
    if [[ "$SIZE" == "$LENGTH" ]]; then
        pass "$LABEL: size $SIZE = length"
    else
        fail "$LABEL: downloaded $SIZE bytes, length=$LENGTH"
    fi

    if xcrun swift scripts/verify-ed-signature.swift "$PUBLIC_KEY" "$SIGNATURE" "$ZIP"; then
        pass "$LABEL: signature valid for SUPublicEDKey"
    else
        fail "$LABEL: signature not valid for SUPublicEDKey (the app would reject the update)"
    fi
    if [[ -x "$SPARKLE_BIN/sign_update" && -x "$SPARKLE_BIN/generate_keys" ]]; then
        if [[ "$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null)" != "$PUBLIC_KEY" ]]; then
            fail "$LABEL: the Keychain signing key does not belong to SUPublicEDKey"
        elif "$SPARKLE_BIN/sign_update" --verify "$ZIP" "$SIGNATURE" >/dev/null 2>&1; then
            pass "$LABEL: sign_update --verify"
        else
            fail "$LABEL: sign_update --verify rejected the signature"
        fi
    fi
done

# --- Installed build ---------------------------------------------------------

if [[ -n "$INSTALLED_BUILD" ]]; then
    if [[ "$NEWEST" -gt "$INSTALLED_BUILD" ]]; then
        pass "newest build $NEWEST > installed build $INSTALLED_BUILD: the update is offered"
    else
        fail "newest build $NEWEST is not greater than installed build $INSTALLED_BUILD: no update is offered"
    fi
fi

finish
