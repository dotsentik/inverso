# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.12] - 2026-10-26

### Changed

- New app icon
- Custom menu bar icon

## [1.2.11] - 2026-10-26

### Changed

- Conversion sound is now a custom one

## [1.2.10] - 2026-10-26

### Fixed

- The conversion log records the layouts the conversion actually used; with a custom
  "Convert to" layout it no longer shows the first other enabled layout as the target.

## [1.2.9] - 2026-10-25

### Changed

- Refactored app architecture around a single Composition Root (`InversoApp` / `AppDelegate`)
  and extracted a pure `Inverso/Core` conversion engine (`Foundation` only) with cached
  layout maps (`LayoutMapProviding`).
- Introduced extension seams for application focus rules (`AppRuleRegistry`), text access
  strategies (`TextAccessStrategy`), user feedback (`FeedbackProviding`), hotkey triggers
  (`HotkeyTrigger`), Sparkle updater driving (`UpdaterDriving`), and centralized
  `UserDefaults` keys (`SettingsKeys`).
- Reduced idle resource usage and startup time (~30% faster launch): lazy SQLite connection
  and background serial write queue in `ConversionLogStore`, reusable `NSPanel` /
  `NSHostingView` in `ConversionHUD`, deferred updater startup, and `.task`-scoped
  permission checks in `PermissionsView`.
- Reduced app bundle size by ~40% (from 8.3 MB to 5.0 MB) and executable binary size by
  ~58% through dead-code stripping, asset catalog space optimization, and pruning unused
  Sparkle `XPCServices` and localizations.

## [1.2.8] - 2026-10-20

### Fixed

- Fixed ё (and other keys) on ISO keyboards: the key left of 1 was missing from the layout
  maps. In Russian – PC it types ё and Ё, so “§krf” now converts to “ёлка” and “ёлка” back
  to “§krf”. Other layouts get their characters on that key too: ^ and ° in German, @ and #
  in French, º and ª in Spanish – ISO, \ and / in Ukrainian – PC.
- Characters on that key that another key also types keep converting through that other key,
  as before (ё through the grave key on ANSI keyboards, > in Russian – Phonetic).
- Greedy Line: a character typed right before the first converted word converts with it
  (“2025 §krf” → “2025 ёлка”, not “2025 §лка”).

## [1.2.7] - 2026-10-20 (formerly LangSwitcher)

Renamed from LangSwitcher to Inverso. New bundle identifier: install manually; updates
from older LangSwitcher builds are not possible. See “Migrating from LangSwitcher” in the
README.

The history of this repository starts with this version. Version 1.2.6 and earlier were
published as LangSwitcher: <https://github.com/dotsentik/LangSwitcher>.

### Changed

- App, target, scheme and project renamed to Inverso (`Inverso.app`, `Inverso.xcodeproj`,
  test target `InversoTests`).
- Bundle identifier `com.dotsentik.inverso` (tests: `com.dotsentik.inversoTests`).
- Log subsystem `com.inverso.app`.
- The conversion log is stored in `~/Library/Application Support/Inverso`. On the first
  launch the log from `~/Library/Application Support/LangSwitcher` is copied there; the
  old directory is kept.
- Update feed: `https://raw.githubusercontent.com/dotsentik/inverso/main/appcast.xml`;
  release archives are named `Inverso-<version>.zip`. The update signing key is unchanged.
- Release builds are signed with the “Inverso Release” certificate by default.
- About panel: “Based on LangSwitcher by LayoutSwitcher Contributors” with a link to the
  original project.
- LICENSE: the original copyright notice is kept, the second line is now Inverso Dev.
- README and CONTRIBUTING: fork notice rewritten, migration steps for LangSwitcher users.

## [1.2.6] - 2026-10-20

The history of the LangSwitcher repository starts with this version.

### Added

- Automatic updates through Sparkle: a daily check against `appcast.xml` in this
  repository, a **Check for Updates…** menu item and a switch in Settings → General.
  Updates are verified with an EdDSA signature before they are installed.
- A hint in terminal apps (Terminal, iTerm2, Ghostty, Alacritty and others): the hotkey
  shows “not supported” instead of sending keystrokes or touching the clipboard.
- About panel: a link to the original project and its license.

### Changed

- Universal build: runs natively on Apple Silicon and Intel Macs (macOS 15 or later).
- Spotlight on newer macOS, where its field belongs to another process: the field is
  found again, and the word or line before the cursor is selected through Accessibility
  instead of keystrokes. An inline completion offered by Spotlight is not converted.
- Spotlight and Open/Save panels: keystrokes go to the window with the keyboard focus,
  not to the app behind it.
- Version numbering: 1.2.N, where N is the build number. About LangSwitcher shows only
  the version (“Version 1.2.6”), without the build number in parentheses.
- Releases are signed with the same certificate every time, so the Accessibility
  permission is kept across updates.
- Release builds contain no absolute paths of the build machine.
- README (English and Russian) rewritten: installation, updates, limitations and a
  section about this fork. LICENSE has a second copyright line; the original notice is
  unchanged.

### Fixed

- Conversion in Spotlight with an empty selection (Smart Conversion: Last Word and
  Greedy Line).
- Update errors are logged with the error domain, code and the feed's HTTP status.

[Unreleased]: https://github.com/dotsentik/inverso/compare/v1.2.12...HEAD
[1.2.12]: https://github.com/dotsentik/inverso/compare/v1.2.11...v1.2.12
[1.2.11]: https://github.com/dotsentik/inverso/compare/v1.2.10...v1.2.11
[1.2.10]: https://github.com/dotsentik/inverso/compare/v1.2.9...v1.2.10
[1.2.9]: https://github.com/dotsentik/inverso/compare/v1.2.8...v1.2.9
[1.2.8]: https://github.com/dotsentik/inverso/releases/tag/v1.2.8
[1.2.7]: https://github.com/dotsentik/inverso/releases/tag/v1.2.7
[1.2.6]: https://github.com/dotsentik/LangSwitcher/releases/tag/v1.2.6
