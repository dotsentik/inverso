# Contributing

## Branches

- `main` is always releasable.
- Work happens in `feat/…`, `fix/…` or `chore/…` branches and lands in `main` through a
  pull request, merged with **squash merge**.

## Commits

- Subject in the imperative mood (“Add…”, “Fix…”), up to ~70 characters, no trailing period.
- The body explains *why*, not what the diff already shows.
- One commit = one logical change.
- In English.

## Tests

Tests are required: run them after every change to Swift code, and add tests for new
behavior and bug fixes. CI runs the same command on every push to `main` and every pull
request; it only runs the tests, releases are built locally.

```bash
xcodebuild test \
  -project Inverso.xcodeproj \
  -scheme Inverso \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

Format with `xcrun swift-format format --in-place --recursive Inverso InversoTests`.

## Versioning

- The version has the form **1.2.N**, where **N = `CURRENT_PROJECT_VERSION`** (the build
  number, `CFBundleVersion`, which Sparkle compares). Every release raises both:
  1.2.7 is build 7, the next release is 1.2.8 with build 8, and so on.
- `MARKETING_VERSION` is the version users see (“Version 1.2.7” in About Inverso);
  the release tag is `v<MARKETING_VERSION>` (annotated), e.g. `v1.2.7`.
- `scripts/release.sh` stops if `MARKETING_VERSION` is not `1.2.` + `CURRENT_PROJECT_VERSION`.
- The `1.2` part changes only by hand, for major changes. The rule then becomes X.Y.N,
  N is still the build number: update `VERSION_PREFIX` in `scripts/release.sh` and this
  section together.
- Changes are listed in [CHANGELOG.md](CHANGELOG.md), one section per version.

## Releasing

A feed entry goes into the committed `appcast.xml` only after its zip is attached to the
GitHub Release; until then installed copies keep seeing “no updates”.

1. Raise `CURRENT_PROJECT_VERSION` and set `MARKETING_VERSION` to `1.2.<build>` (see
   [Versioning](#versioning)), update `CHANGELOG.md`.
2. Commit the changes and build: `scripts/release.sh`. It produces
   `dist/Inverso-<version>.zip`, `dist/appcast.xml` and `dist/release-notes.md`.
3. Push `main` and put an annotated tag `v<version>` on the commit with this version:
   `git tag -a v<version> -m "Inverso <version>"`, `git push origin main v<version>`.
4. The repository must be public, otherwise Sparkle can download neither the feed nor the zip.
5. Create the GitHub Release for the tag with the zip and the notes:
   `gh release create v<version> dist/Inverso-<version>.zip --title "Inverso <version>" --notes-file dist/release-notes.md`
6. Run `scripts/apply-appcast.sh`, then commit `appcast.xml` on its own as
   “Publish appcast for v<version>” and push.
7. Wait up to 5 minutes (raw.githubusercontent.com caches files) and run
   `scripts/check-feed.sh --installed-build <previous build>`.
8. Check on a real Mac: install the previous build (one with Sparkle), choose
   **Check for Updates…**, make sure the update is found, downloaded and installed, the app
   relaunches and the Accessibility permission is still granted.

Keep the update signing key (EdDSA, in the login Keychain) and the “Inverso Release”
code signing certificate outside the repository and back them up
(`generate_keys -x <file>`, export as `.p12`). Without the key no update can be published
for copies that are already installed.

## Building

```bash
xcodebuild build \
  -project Inverso.xcodeproj \
  -scheme Inverso \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-"
```

The app is at `build/Build/Products/Release/Inverso.app`. Xcode fetches [Sparkle](https://github.com/sparkle-project/Sparkle) 2.10.0 through Swift Package Manager and embeds `Sparkle.framework` in `Contents/Frameworks`. Requires Xcode 26 or later (Swift 6; the app icon is an Icon Composer `.icon` file).

Setup notes:

- Swift 6 with complete strict concurrency checking; deployment target macOS 15.0. The project setting is `ARCHS = arm64` for local builds; `scripts/release.sh` builds universal (`arm64 x86_64`).
- No App Sandbox: reading and replacing text in other apps needs Accessibility and synthetic keystrokes.
- Hardened Runtime is on. `Inverso/Inverso.entitlements` has `com.apple.security.cs.disable-library-validation`: without an Apple Team ID (ad hoc or self-signed certificate), library validation refuses to load the embedded `Sparkle.framework`.

## Project layout

```
Inverso/
├── App/                       entry point, AppDelegate (startup only)
├── Features/
│   ├── Conversion/            conversion pipeline, layout mapping, target layout choice
│   ├── HUD/                   overlay shown after a conversion
│   ├── MenuBar/               menu bar menu, About panel
│   └── Settings/              Settings window and its sections
├── Services/
│   ├── Layouts/               system input sources, character maps (UCKeyTranslate)
│   ├── TextAccess/            Accessibility, clipboard, keystrokes, focus detection
│   ├── Updates/               Sparkle updater and its configuration (UpdateConfig)
│   └── ...                    settings, hotkey, localization, log store, logging
├── Models/
└── Resources/                 Localizable.xcstrings (en, ru), icon, assets
InversoTests/                  XCTest unit tests
scripts/release.sh             release build, signing, archive, appcast entry
scripts/apply-appcast.sh       publishes the feed entry after the GitHub Release
scripts/check-feed.sh          checks the published update feed and archive
scripts/verify-ed-signature.swift  EdDSA check with SUPublicEDKey (used by the scripts)
docs/                          README media
CHANGELOG.md, CONTRIBUTING.md  changes per version; branches, commits, releasing
appcast.xml                    Sparkle update feed
```

## Troubleshooting updates

Sparkle shows “Update Error” when it can't load the update feed or the archive, or the archive fails verification:

- **the repository is private:** the feed on `raw.githubusercontent.com` and the release download answer 404 to anonymous requests;
- **no release or feed yet:** the GitHub Release has no zip, or `appcast.xml` with the entry is not in `main`;
- **wrong signature:** the archive is not signed with the key whose public part is in the app (`SUPublicEDKey`); Sparkle refuses to install it;
- **cache:** `raw.githubusercontent.com` caches files for up to ~5 minutes, so a just-published feed may still be the old one; try again later.

To see which of these it is, run in a clone of the repository:

```bash
scripts/check-feed.sh --installed-build <your build>
```

Your build is the number in parentheses in the update dialog, and is equal to the last number of the version (“Version 1.2.7” is build 7). The app also logs the error domain, code and the feed's HTTP status: `log show --last 10m --predicate 'subsystem == "com.inverso.app"'`.

## Never commit

`dist/`, `build/`, keys and certificates (`.p12`, `.pem`, `.key`, `.cer`), logs, `*.zip`,
`*.dmg`, `*.profraw`.
