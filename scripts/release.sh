#!/bin/bash
# Builds a release of Inverso and prepares it for publishing:
#   Release build → code signing → checks → dist/Inverso-<version>.zip (+ .sha256,
#   INSTALL.txt) → EdDSA signature (sign_update) → dist/appcast.xml with one <item> for
#   this version, and dist/release-notes.md from the version's section of CHANGELOG.md.
#
# Nothing is published and appcast.xml in the repository root is not changed: an entry
# goes there (scripts/apply-appcast.sh) only after the zip is attached to the GitHub
# Release, otherwise installed copies would be offered a download that doesn't exist.
# The publishing steps are printed at the end (see CONTRIBUTING.md, Releasing).
#
# Usage: scripts/release.sh
# Environment:
#   ARCHS          architectures to build (default: "arm64 x86_64", universal)
#   SIGN_IDENTITY  codesign identity (default: "Inverso Release", a self-signed
#                  certificate in the login Keychain; "-" signs ad hoc)
#
# Every release must be signed with the same certificate: macOS keeps the Accessibility
# permission only while the designated requirement stays the same. Ad hoc signatures
# change it with every build, so users would have to grant access again after each update.
#
# The version comes from MARKETING_VERSION and CURRENT_PROJECT_VERSION in the project.
# Numbering rule (CONTRIBUTING.md, Versioning): MARKETING_VERSION is VERSION_PREFIX + "." +
# CURRENT_PROJECT_VERSION, e.g. 1.2.6 for build 6. The prefix changes only by hand, for
# major changes; update VERSION_PREFIX below then.
# CURRENT_PROJECT_VERSION becomes CFBundleVersion, which Sparkle compares: it must be
# greater than every version already published in appcast.xml.
#
# Absolute paths of the build machine (they contain the macOS user name of whoever built
# it) are kept out of the app in two layers:
#   - the compilers map the project directory to /src and the build directory to /build
#     (-file-prefix-map / -debug-prefix-map for Swift, -ffile-prefix-map for Clang), so
#     #filePath / #file in assert, precondition and fatalError and the DWARF carry no
#     /Users/ paths;
#   - the binaries are stripped (STRIP_INSTALLED_PRODUCT and strip -S -x) of the debug map
#     (N_SO/N_OSO/N_SOL symbols), which also lists the absolute paths of the object files.
# The build fails if "/Users/" is left in any slice of the app or Sparkle binary, or
# anywhere in the app. The dSYM with full debug information stays in build/dist-derived
# for symbolicating crash reports.
#
# The update signing key is read from the login Keychain by sign_update (created once
# with generate_keys). No secrets are stored in this script or in the repository.

set -euo pipefail

ARCHS="${ARCHS:-arm64 x86_64}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Inverso Release}"
# Major and minor part of MARKETING_VERSION; the patch part is the build number.
VERSION_PREFIX="1.2"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PROJECT="Inverso.xcodeproj"
SCHEME="Inverso"
DERIVED="build/dist-derived"
DIST="dist"
# The published feed (read only here) and the one prepared for this release.
INVERSO_APPCAST="${INVERSO_APPCAST:-appcast.xml}"
DIST_APPCAST="$DIST/appcast.xml"
RELEASE_NOTES="$DIST/release-notes.md"
CHANGELOG="CHANGELOG.md"
DOWNLOAD_BASE="https://github.com/dotsentik/inverso/releases/download"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() {
    echo "error: $*" >&2
    exit 1
}

step() {
    echo
    echo "==> $*"
}

# --- Version -----------------------------------------------------------------

step "Reading the version"
SETTINGS="$(xcodebuild -project "$PROJECT" -target "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null)"
VERSION="$(awk -F' = ' '$1 ~ /^ *MARKETING_VERSION$/ { print $2; exit }' <<<"$SETTINGS")"
BUILD="$(awk -F' = ' '$1 ~ /^ *CURRENT_PROJECT_VERSION$/ { print $2; exit }' <<<"$SETTINGS")"
MIN_SYSTEM="$(awk -F' = ' '$1 ~ /^ *MACOSX_DEPLOYMENT_TARGET$/ { print $2; exit }' <<<"$SETTINGS")"
[[ -n "$VERSION" && -n "$BUILD" ]] || fail "MARKETING_VERSION or CURRENT_PROJECT_VERSION not found"
[[ "$BUILD" =~ ^[0-9]+$ ]] || fail "CURRENT_PROJECT_VERSION must be an integer, got '$BUILD'"
[[ "$VERSION" == "$VERSION_PREFIX.$BUILD" ]] ||
    fail "MARKETING_VERSION is $VERSION, but CURRENT_PROJECT_VERSION is $BUILD: by the numbering rule MARKETING_VERSION must be $VERSION_PREFIX.$BUILD (see CONTRIBUTING.md, Versioning)"
echo "Version $VERSION (build $BUILD), macOS $MIN_SYSTEM+, archs: $ARCHS, identity: $SIGN_IDENTITY"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
    security find-identity -v -p codesigning | grep -qF "\"$SIGN_IDENTITY\"" ||
        fail "code signing identity '$SIGN_IDENTITY' not found in the Keychain (see README, Releasing)"
fi

if [[ -f "$INVERSO_APPCAST" ]]; then
    LATEST_BUILD="$(sed -n 's/.*<sparkle:version>\([0-9]*\)<\/sparkle:version>.*/\1/p' "$INVERSO_APPCAST" | sort -n | tail -1)"
    if [[ -n "$LATEST_BUILD" && "$BUILD" -le "$LATEST_BUILD" ]]; then
        fail "CURRENT_PROJECT_VERSION ($BUILD) must be greater than the latest build in $INVERSO_APPCAST ($LATEST_BUILD)"
    fi
fi

ZIP_NAME="Inverso-$VERSION.zip"
ZIP_URL="$DOWNLOAD_BASE/v$VERSION/$ZIP_NAME"

# The section "## [<version>] ..." up to the next "## [" heading, without its own heading.
NOTES="$(awk -v version="$VERSION" '
    /^## \[/ { if (found) exit; if (index($0, "## [" version "]") == 1) { found = 1; next } }
    found { print }
' "$CHANGELOG" 2>/dev/null || true)"
[[ -n "${NOTES//[[:space:]]/}" ]] || fail "$CHANGELOG has no section '## [$VERSION]'"

# --- Build -------------------------------------------------------------------

step "Building Release"
# Build settings split values on spaces, so the prefix maps need paths without them.
[[ "$REPO_ROOT" != *" "* ]] || fail "the project path must not contain spaces: $REPO_ROOT"
# The build directory first: it lies inside the project directory.
PREFIX_MAPS_SWIFT="-file-prefix-map $REPO_ROOT/$DERIVED=/build -file-prefix-map $REPO_ROOT=/src"
PREFIX_MAPS_SWIFT+=" -debug-prefix-map $REPO_ROOT/$DERIVED=/build -debug-prefix-map $REPO_ROOT=/src"
PREFIX_MAPS_CLANG="-ffile-prefix-map=$REPO_ROOT/$DERIVED=/build -ffile-prefix-map=$REPO_ROOT=/src"
# A second try: Finder may write .DS_Store into a folder while it is being deleted.
rm -rf "$DIST" "$DERIVED" 2>/dev/null || rm -rf "$DIST" "$DERIVED"
xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED" \
    ARCHS="$ARCHS" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    OTHER_SWIFT_FLAGS="\$(inherited) $PREFIX_MAPS_SWIFT" \
    OTHER_CFLAGS="\$(inherited) $PREFIX_MAPS_CLANG" \
    DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
    DEPLOYMENT_POSTPROCESSING=YES \
    DEAD_CODE_STRIPPING=YES \
    STRIP_INSTALLED_PRODUCT=YES \
    STRIP_STYLE=all \
    -quiet

BUILT_APP="$DERIVED/Build/Products/Release/Inverso.app"
[[ -d "$BUILT_APP" ]] || fail "build product not found: $BUILT_APP"
SPARKLE_BIN="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin"
[[ -x "$SPARKLE_BIN/sign_update" ]] || fail "sign_update not found in $SPARKLE_BIN"

mkdir -p "$DIST"
APP="$DIST/Inverso.app"
ditto "$BUILT_APP" "$APP"
BINARY="$APP/Contents/MacOS/Inverso"

step "Optimizing bundle resources"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
[[ -d "$SPARKLE" ]] || fail "Sparkle.framework is not embedded in the app"
SPARKLE_B="$SPARKLE/Versions/B"

# Remove unused XPCServices (not needed without App Sandbox)
rm -rf "$SPARKLE_B/XPCServices"

# Prune Sparkle localizations except Base, en, ru
for lproj in "$SPARKLE_B"/Resources/*.lproj; do
    name="$(basename "$lproj" .lproj)"
    case "$name" in
        Base|en|ru) ;;
        *) rm -rf "$lproj" ;;
    esac
done

step "Stripping debug symbols"
# The signature is redone below; removing it first keeps strip from warning about it.
codesign --remove-signature "$BINARY"
strip -S -x "$BINARY"

# --- Signing -----------------------------------------------------------------

step "Signing with '$SIGN_IDENTITY'"
# Inside out: Sparkle's helpers, the framework, then the app. Hardened Runtime everywhere.
SIGN=(codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY")
if [[ -d "$SPARKLE_B/XPCServices" ]]; then
    for xpc in "$SPARKLE_B"/XPCServices/*.xpc; do
        [[ -e "$xpc" ]] && "${SIGN[@]}" --preserve-metadata=entitlements "$xpc"
    done
fi
"${SIGN[@]}" "$SPARKLE_B/Autoupdate"
"${SIGN[@]}" "$SPARKLE_B/Updater.app"
"${SIGN[@]}" "$SPARKLE"
# The entitlement lets the app load Sparkle.framework: without a Team ID (ad hoc or a
# self-signed certificate) library validation rejects it.
"${SIGN[@]}" --entitlements Inverso/Inverso.entitlements "$APP"

# --- Checks ------------------------------------------------------------------

step "Checking the app"
echo "Architectures: $(lipo -archs "$BINARY")"
for arch in $ARCHS; do
    lipo "$BINARY" -verify_arch "$arch" || fail "the binary has no $arch slice"
done
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvv "$APP" 2>&1 | grep -E '^(Identifier|Authority|Signature|TeamIdentifier|CodeDirectory)'
codesign -d -r- "$APP" 2>&1 | grep designated
codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q disable-library-validation ||
    fail "the app is signed without Inverso.entitlements"
# Markers of features that must be in the build. TerminalApps has no type metadata, so
# after stripping only its bundle IDs show it is there.
for marker in KeyboardFocusOwner com.mitchellh.ghostty org.alacritty; do
    for arch in $(lipo -archs "$BINARY"); do
        lipo "$BINARY" -thin "$arch" -output "$WORK/slice"
        grep -aqF "$marker" "$WORK/slice" || fail "'$marker' is missing from the $arch slice"
    done
    echo "$marker: present in every slice"
done
# No absolute paths of the build machine (they reveal the user name): every slice of the
# app and Sparkle binaries, then every file of the app.
for binary in "$BINARY" "$SPARKLE_B/Sparkle"; do
    for arch in $(lipo -archs "$binary"); do
        lipo "$binary" -thin "$arch" -output "$WORK/slice"
        if grep -aqF "/Users/" "$WORK/slice"; then
            fail "the $arch slice of ${binary#"$APP/"} contains $(grep -aoF "/Users/" "$WORK/slice" | wc -l | tr -d ' ') occurrences of /Users/"
        fi
    done
done
if LEAKS="$(grep -rlaF "/Users/" "$APP")"; then
    fail "/Users/ found in: $LEAKS"
fi
if LEAKS="$(grep -rlaF "$DERIVED/" "$APP")"; then
    fail "$DERIVED/ paths found in: $LEAKS"
fi
echo "/Users/: 0 occurrences in every slice and in the whole app"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
PLIST_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
[[ "$PLIST_VERSION" == "$VERSION" && "$PLIST_BUILD" == "$BUILD" ]] ||
    fail "Info.plist says $PLIST_VERSION ($PLIST_BUILD), expected $VERSION ($BUILD)"
/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist" >/dev/null ||
    fail "SUPublicEDKey is missing from Info.plist"

# --- Package -----------------------------------------------------------------

step "Packaging $ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$ZIP_NAME"
(cd "$DIST" && shasum -a 256 "$ZIP_NAME" >"$ZIP_NAME.sha256")
cat "$DIST/$ZIP_NAME.sha256"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    ACCESS_NOTE="   Сборка подписана ad hoc: macOS считает каждую новую версию другим
   приложением, и после обновления доступ перестаёт действовать, хотя
   переключатель в списке остаётся включённым. После каждого обновления:
   выделить Inverso в списке, удалить его кнопкой «−», добавить заново
   кнопкой «+», включить переключатель и перезапустить приложение."
else
    ACCESS_NOTE="   Все версии Inverso подписаны одним и тем же сертификатом, поэтому
   доступ сохраняется при обновлениях. Если конвертация вдруг перестала
   работать: выделить Inverso в списке, удалить его кнопкой «−», добавить
   заново кнопкой «+», включить переключатель и перезапустить приложение.

   Переход с LangSwitcher (прежнее название): удалить старую копию
   LangSwitcher из «Программ» и убрать её из списка «Универсальный доступ»
   кнопкой «−». Обновиться с LangSwitcher автоматически нельзя. Старый
   журнал конвертаций копируется при первом запуске Inverso."
fi

cat >"$DIST/INSTALL.txt" <<EOF
Inverso $VERSION (сборка $BUILD) — установка
=====================================

Требования: macOS $MIN_SYSTEM или новее; архитектуры: $(lipo -archs "$BINARY").
Приложение не подписано сертификатом Apple Developer и не нотаризовано,
поэтому при первом запуске macOS выдаст предупреждение — это ожидаемо.

0. (Необязательно) Проверить целостность архива
   В Терминале, в папке с архивом:
     shasum -a 256 -c $ZIP_NAME.sha256
   Должно быть: $ZIP_NAME: OK

1. Установка
   Закрыть Inverso, если он запущен (значок в строке меню →
   «Завершить Inverso»). Распаковать $ZIP_NAME (двойной клик)
   и перетащить Inverso.app в папку «Программы» (/Applications),
   заменив старую копию.

2. Первый запуск
   В /Applications: правый клик по Inverso → «Открыть» → «Открыть».
   Значок приложения (клавиатура) появится в строке меню.

   Если macOS пишет, что приложение повреждено или его нельзя открыть,
   выполнить в Терминале:
     xattr -dr com.apple.quarantine /Applications/Inverso.app
   и снова запустить приложение.

3. Универсальный доступ (обязательно)
   Системные настройки → Конфиденциальность и безопасность →
   Универсальный доступ. Включить переключатель рядом с Inverso
   (если его нет в списке — нажать «+» и выбрать его в /Applications).

$ACCESS_NOTE

4. Проверка
   В любом текстовом поле (например, в Заметках) напечатать в английской
   раскладке:
     ghbdtn
   и дважды быстро нажать Shift (⇧⇧). Должно получиться: привет
   Горячую клавишу можно изменить: значок в строке меню → Настройки → Клавиши.

5. Обновления
   Раз в сутки приложение проверяет на GitHub, не вышла ли новая версия
   (отключается в Настройки → Основные). Проверить вручную: значок в строке
   меню → «Проверить обновления…».

6. Если что-то не работает
   Открыть Console.app (Программы → Утилиты → Консоль), выбрать этот Mac,
   нажать «Начать трансляцию», в поиске ввести com.inverso.app, повторить
   действие, которое не работает, и прислать найденные строки лога.
EOF

# --- Update signature and appcast ----------------------------------------------

step "Signing the update (EdDSA key from the Keychain)"
# Prints: sparkle:edSignature="…" length="…"
SIGNATURE_ATTRS="$("$SPARKLE_BIN/sign_update" "$DIST/$ZIP_NAME")"
[[ "$SIGNATURE_ATTRS" == *'sparkle:edSignature='* ]] || fail "sign_update failed"
echo "$SIGNATURE_ATTRS"

step "Writing $DIST_APPCAST"
# The whole feed with only this version: Sparkle needs just the newest item, and
# scripts/apply-appcast.sh copies the file to the repository root after the release.
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
cat >"$DIST_APPCAST" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Inverso</title>
        <link>https://raw.githubusercontent.com/dotsentik/inverso/main/appcast.xml</link>
        <description>Inverso updates</description>
        <language>en</language>
        <item>
            <title>Version $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$MIN_SYSTEM</sparkle:minimumSystemVersion>
            <sparkle:releaseNotesLink>https://github.com/dotsentik/inverso/releases/tag/v$VERSION</sparkle:releaseNotesLink>
            <enclosure url="$ZIP_URL" $SIGNATURE_ATTRS type="application/octet-stream"/>
        </item>
    </channel>
</rss>
EOF
xmllint --noout "$DIST_APPCAST" || fail "$DIST_APPCAST is not valid XML"
grep -q "<sparkle:version>$BUILD</sparkle:version>" "$DIST_APPCAST" || fail "$DIST_APPCAST lacks build $BUILD"

step "Writing $RELEASE_NOTES"
# Leading blank lines dropped
printf '%s\n' "$NOTES" | sed -e '/./,$!d' >"$RELEASE_NOTES"
echo "$(wc -l <"$RELEASE_NOTES" | tr -d ' ') lines from $CHANGELOG"

# --- Done --------------------------------------------------------------------

step "Done"
ls -l "$DIST"
cat <<EOF

Nothing has been published. To publish $VERSION (build $BUILD), see CONTRIBUTING.md:

  1. Commit the changes, push main, tag the version commit (annotated) and push the tag:
       git push origin main
       git tag -a v$VERSION -m "Inverso $VERSION"
       git push origin v$VERSION
  2. The repository must be public: Sparkle downloads the feed and the zip anonymously.
  3. Create the GitHub Release with the zip and the notes:
       gh release create v$VERSION $DIST/$ZIP_NAME --title "Inverso $VERSION" --notes-file $RELEASE_NOTES
  4. Publish the feed entry, in a commit of its own:
       scripts/apply-appcast.sh
       git add $INVERSO_APPCAST
       git commit -m "Publish appcast for v$VERSION"
       git push origin main
  5. After up to 5 minutes (raw.githubusercontent.com cache):
       scripts/check-feed.sh --installed-build <previous build>
EOF
