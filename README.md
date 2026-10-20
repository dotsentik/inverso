# Inverso

[English](README.md) | [Русский](README.ru.md)

A menu bar app for macOS that fixes text typed in the wrong keyboard layout. Typed `ghbdtn? rfr ltkf&` instead of `привет, как дела?` — press `⇧⇧` (Shift twice) and the text is converted in place.

Inverso is an unofficial fork of LangSwitcher by LayoutSwitcher Contributors; see [About this fork](#about-this-fork).

Changes: [CHANGELOG.md](CHANGELOG.md). Contributing and releasing: [CONTRIBUTING.md](CONTRIBUTING.md).

## Install

1. Download `Inverso-<version>.zip` from [Releases](https://github.com/dotsentik/inverso/releases).
2. Quit Inverso if it is running (menu bar icon → Quit Inverso).
3. Unzip the archive and move `Inverso.app` to `/Applications`, replacing the old copy.
4. First launch: in `/Applications`, right-click Inverso → **Open** → **Open**. The app is not notarized by Apple, so a plain double-click is blocked the first time. If macOS says the app is damaged or can't be opened, run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Inverso.app
   ```
5. Grant **Accessibility** access: System Settings → Privacy & Security → Accessibility → turn on Inverso (if it is not in the list, add it with “+”). Without this permission the app cannot read or replace text.

The keyboard icon appears in the menu bar. Settings → Permissions shows whether access is granted.

Only the first installation is manual. After that, updates come through the app: menu bar icon → **Check for Updates…**, or the automatic daily check (see [Updates](#updates)).

### Accessibility access and updates

macOS keeps the Accessibility permission only for an app with the same code signature. Every Inverso release is signed with the same certificate, so access stays granted after updates, including updates installed by the app itself.

If conversion ever stops working while the switch is on: in the Accessibility list, select Inverso, remove it with “−”, add `/Applications/Inverso.app` with “+”, turn it on and relaunch the app.

### Migrating from LangSwitcher

Inverso was called LangSwitcher before version 1.2.7. It has a new bundle identifier, so LangSwitcher cannot update itself to Inverso; install it manually once:

1. Quit LangSwitcher and delete it from `/Applications`.
2. Remove LangSwitcher from the Accessibility list: System Settings → Privacy & Security → Accessibility, select it, click “−”.
3. Install Inverso manually (see [Install](#install)).
4. Grant Inverso Accessibility access.
5. Optional: the conversion log is copied on the first launch if `~/Library/Application Support/Inverso` does not exist yet. To copy it by hand, quit Inverso and copy `~/Library/Application Support/LangSwitcher/conversion_log.sqlite` to `~/Library/Application Support/Inverso/`.

## Usage

1. Type text in any app.
2. Press `⇧⇧`. If text is selected, the selection is converted; otherwise Smart Conversion picks the text before the cursor.
3. The menu bar icon has: Convert Text, the list of keyboard layouts (click one to switch to it), Settings… (`⌘,`), About Inverso, Check for Updates…, Quit (`⌘Q`).

## What it does

### Conversion

- **Converts by physical key position** between any two of your enabled keyboard layouts: `ghbdtn` ↔ `привет`, `руддщ` ↔ `hello`.
- **Uses the layouts installed in macOS.** Character maps are read from the system layouts (`UCKeyTranslate`), so any keyboard layout works. Built-in tables for U.S./ABC/British, Russian, Ukrainian, German, French and Spanish are the fallback when a system map can't be read.
- **Detects the source layout** from the text; on a tie the currently active layout wins. The target is the first layout in your priority order with a different script, or the one you chose for that layout.
- **Punctuation**: after a letter, punctuation converts with the word (`ltkf&` → `дела?`); at the start of a word or on its own it stays as typed, unless the key gives a letter in the target layout (`;` → `ж`).

### Smart Conversion (nothing selected)

- **Greedy (Entire Phrase)** — the default. Selects from the cursor to the line start (`⌘⇧←`), finds where the wrong-layout part begins and converts only that part: in `Привет ghbdtn rfr` only `ghbdtn rfr` changes. A line where all or most words are in the wrong layout converts as a whole.
- **Last Word Only** — selects the word before the cursor (`⌥⇧←`) and converts it if it looks typed in the wrong layout.
- **Disabled** — only an explicit selection is converted.

If nothing is converted, the selection is collapsed so the cursor stays where it was.

### Where it works

- **Most apps**: text is read and replaced through the Accessibility API; if the app doesn't support it, through `⌘C` / `⌘V`.
- **Electron apps** are handled through the clipboard only, because they report Accessibility writes as successful without applying them: Obsidian, Visual Studio Code, Slack, Discord, Notion, and any other app that contains `Electron Framework.framework`.
- **Spotlight and Open/Save dialogs** take keyboard focus without becoming the frontmost app. Inverso detects them and reads the text from them, then types the converted text in.
- **The clipboard** is saved before Inverso uses it and restored afterwards, unless another app wrote to it in the meantime.

### Limitations

- **Terminals are not supported** (Terminal, iTerm2, Ghostty, Warp, kitty, Alacritty, WezTerm): there the hotkey sends no keystrokes, doesn't touch the clipboard and changes no text; the overlay shows “Not supported in the terminal”.

### Feedback

- **Overlay (HUD)** — the default: a small panel at the top of the screen with the mouse, e.g. `ghbdtn → привет · RU`, for about a second. It never takes focus, follows Reduce Motion and Reduce Transparency, and is announced by VoiceOver.
- **Notification** (Notification Center) or **Nothing** can be chosen instead.
- **Sound** (“Tink”) after a conversion, on by default.

### Layout switch after conversion

After a conversion the system layout switches to the layout the text was converted into. Settings offer three modes (always / if the last word was converted / if any word was converted); in the current version all three behave the same and switch the layout after every conversion.

## Settings

The Settings window (`⌘,`) has five sections, switched with the segmented control or `⌘1`…`⌘5`:

- **General** — interface language (System, English, Русский; switches instantly), Launch at Login, automatic update checks, what to show after a conversion (Overlay, Notification, Nothing), sound, Smart Conversion mode, layout switch mode, number of conversions.
- **Layouts** — the keyboard layouts enabled in macOS, in priority order. Drag rows or use `⌥⌘↑` / `⌥⌘↓` to reorder; uncheck a layout (or press Space) to ignore it; “Convert to” sets the target layout (Auto = by priority); Refresh from System picks up changes.
- **Shortcut** — Double Shift (`⇧⇧`, default) or a custom shortcut (`⌥S` until you record another).
- **Permissions** — Accessibility status, buttons to open System Settings and to request access.
- **Log** — off by default. When on, conversions are stored in a local SQLite database (`~/Library/Application Support/Inverso/conversion_log.sqlite`), 100 entries by default or unlimited. Entries can be rated correct/incorrect, deleted, and exported to JSON.

## Network and privacy

- No analytics, no telemetry, no accounts.
- The only network request is the update check: Inverso downloads [`appcast.xml`](appcast.xml) from GitHub (`raw.githubusercontent.com`) and, if you agree to update, the release archive from GitHub Releases. Turn it off in Settings → General → “Check for updates automatically”; then the app makes no network requests unless you choose Check for Updates….
- The conversion log is off by default and never leaves your Mac.
- The app's own logs (unified logging, subsystem `com.inverso.app`) record typed text only at debug level and marked private.

## Updates

- Once a day Inverso checks for a new version (via [Sparkle](https://sparkle-project.org)). When there is one, it shows the release and offers to install it; the update is downloaded, its EdDSA signature is verified, and the app is replaced and relaunched.
- Check manually: menu bar icon → **Check for Updates…**.
- Automatic checks can be turned off in Settings → General.
- Releases with download archives live on [GitHub Releases](https://github.com/dotsentik/inverso/releases); the update feed is [`appcast.xml`](appcast.xml) in the `main` branch.

### If “Update Error” appears

Sparkle shows “Update Error” when it can't load the update feed or the archive, or the archive fails verification:

- **the repository is private:** the feed on `raw.githubusercontent.com` and the release download answer 404 to anonymous requests;
- **no release or feed yet:** the GitHub Release has no zip, or `appcast.xml` with the entry is not in `main`;
- **wrong signature:** the archive is not signed with the key whose public part is in the app (`SUPublicEDKey`); Sparkle refuses to install it;
- **cache:** `raw.githubusercontent.com` caches files for up to ~5 minutes, so a just-published feed may still be the old one; try again later.

To see which of these it is, run in a clone of the repository:

```bash
scripts/check-feed.sh --installed-build <your build>
```

Your build is the last number of the version in About Inverso (“Version 1.2.7” is build 7). The app also logs the error domain, code and the feed's HTTP status: `log show --last 10m --predicate 'subsystem == "com.inverso.app"'`.

## Requirements

- macOS 15 (Sequoia) or later
- Universal build: runs natively on Apple Silicon and Intel Macs (`arm64` + `x86_64`)
- Accessibility permission
- To build: Xcode 26 or later (Swift 6, the app icon is an Icon Composer `.icon` file)

## Build

```bash
xcodebuild build \
  -project Inverso.xcodeproj \
  -scheme Inverso \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-"
```

The app is at `build/Build/Products/Release/Inverso.app`. Xcode fetches [Sparkle](https://github.com/sparkle-project/Sparkle) 2.10.0 through Swift Package Manager and embeds `Sparkle.framework` in `Contents/Frameworks`.

Tests:

```bash
xcodebuild test \
  -project Inverso.xcodeproj \
  -scheme Inverso \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

CI (GitHub Actions) only runs these tests, on pushes to `main` and on pull requests; releases are built locally.

### Build setup

- Swift 6 with complete strict concurrency checking; deployment target macOS 15.0; the project setting is `ARCHS = arm64` for local builds, `scripts/release.sh` builds universal (`arm64 x86_64`).
- No App Sandbox (reading and replacing text in other apps needs Accessibility and synthetic keystrokes).
- Hardened Runtime on. `Inverso/Inverso.entitlements` has `com.apple.security.cs.disable-library-validation`: without an Apple Team ID (ad hoc or self-signed certificate), library validation refuses to load the embedded `Sparkle.framework`.
- Version: **1.2.N, where N = `CURRENT_PROJECT_VERSION`** (`CFBundleVersion`, which Sparkle compares). `MARKETING_VERSION` is shown to users (“Version 1.2.7” in About Inverso); every release raises both: 1.2.7 is build 7, the next one is 1.2.8 with build 8. `scripts/release.sh` stops if they don't match. The `1.2` part changes only by hand, for major changes (the rule becomes X.Y.N, N still the build number); see [CONTRIBUTING.md](CONTRIBUTING.md#versioning).

### Project layout

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
│   └── …                      settings, hotkey, localization, log store, logging
├── Models/
└── Resources/                 Localizable.xcstrings (en, ru), icon, assets
InversoTests/                  XCTest unit tests
scripts/release.sh             release build, signing, archive, appcast entry
scripts/apply-appcast.sh       publishes the feed entry after the GitHub Release
scripts/check-feed.sh          checks the published update feed and archive
scripts/verify-ed-signature.swift  EdDSA check with SUPublicEDKey (used by the scripts)
CHANGELOG.md, CONTRIBUTING.md  changes per version; branches, commits, releasing
appcast.xml                    Sparkle update feed
```

## Releasing

The full checklist, with branches, commits and versions, is in [CONTRIBUTING.md](CONTRIBUTING.md#releasing).

`scripts/release.sh` builds a universal release (`ARCHS`, default `arm64 x86_64`; `SIGN_IDENTITY`, default `Inverso Release`, `-` for ad hoc). It maps the project and build directories to `/src` and `/build` in the compilers, strips the debug map, signs the app, checks the architectures, the signature, the entitlements, the markers of required features, the version in `Info.plist` and that no `/Users/` path is left in any slice or anywhere in the app. It writes `dist/Inverso-<version>.zip` (+ `.sha256`, `INSTALL.txt`), `dist/appcast.xml` with one signed entry and `dist/release-notes.md` from `CHANGELOG.md`. It publishes nothing and does not change `appcast.xml` in the repository root.

**Rule:** an entry goes into the committed `appcast.xml` only after its zip is attached to the GitHub Release. Until then `appcast.xml` stays a valid feed without entries, and installed copies see “no updates” instead of an error.

1. Raise `CURRENT_PROJECT_VERSION` and set `MARKETING_VERSION` to `1.2.<build>`, update `CHANGELOG.md`.
2. Commit the changes and build: `scripts/release.sh` (produces `dist/Inverso-<version>.zip`, `dist/appcast.xml`, `dist/release-notes.md`).
3. Push `main` and put an annotated tag `v<version>` on the commit with this version.
4. The repository must be public, otherwise Sparkle can download neither the feed nor the zip.
5. Create the GitHub Release for the tag with the zip and the notes:
   ```bash
   gh release create v<version> dist/Inverso-<version>.zip --title "Inverso <version>" --notes-file dist/release-notes.md
   ```
6. Run `scripts/apply-appcast.sh` (it checks the entry, the zip size, the signature, the build number and that the zip is downloadable, then copies `dist/appcast.xml` to the root), then commit `appcast.xml` on its own as “Publish appcast for v<version>” and push.
7. Wait up to 5 minutes (raw.githubusercontent.com caches files) and run `scripts/check-feed.sh --installed-build <previous build>`. It prints PASS/FAIL for every check and exits with 1 on any failure.
8. Check on a real Mac: install the previous build (one with Sparkle), choose **Check for Updates…**, make sure the update is found, downloaded and installed, the app relaunches and the Accessibility permission is still granted.

> **Warning.** Keep the update signing key (EdDSA) and the “Inverso Release” certificate outside the repository and make backups: `generate_keys -x <file outside the repository>` and an export to `.p12`. If the key is lost, no update can be published for copies that are already installed.

- **Update signing key (EdDSA).** Created once with Sparkle's `generate_keys` (in `build/dist-derived/SourcePackages/artifacts/sparkle/Sparkle/bin/` after `scripts/release.sh`); the private key is stored in the login Keychain, the public key is `SUPublicEDKey` in `Info.plist`. Back it up with `generate_keys -x <file outside the repository>`, restore it on another Mac with `generate_keys -f <file>`.
- **Code signing certificate.** A self-signed “Inverso Release” certificate in the login Keychain. Keep it: releases signed with another certificate lose the Accessibility permission on update. Export it with Keychain Access → My Certificates → Inverso Release → File → Export Items… (`.p12`, with a password), and keep the file outside the repository.

## About this fork

Inverso is an unofficial fork of LangSwitcher by LayoutSwitcher Contributors, <https://github.com/reg2005/langSwitcher>, distributed under the MIT License. The author of the original project is not affiliated with this fork and is not responsible for it. Report problems with Inverso here, not to the original project.

Main differences from the original:

- Swift 6 with strict concurrency checking.
- Character maps read from the layouts installed in macOS (`UCKeyTranslate`) instead of fixed tables only.
- SwiftUI interface: menu bar menu and a Settings window with sections.
- HUD overlay after a conversion instead of notifications (notifications remain an option).
- Localization: English and Russian, with an in-app language choice.
- Reading and replacing the selection through the Accessibility API, with the clipboard as fallback and for Electron apps.
- Conversion in Spotlight and Open/Save dialogs.
- Automatic updates through Sparkle.

## License

[MIT](LICENSE)
