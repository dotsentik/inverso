# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/dotsentik/inverso/compare/v1.2.7...HEAD
[1.2.7]: https://github.com/dotsentik/inverso/releases/tag/v1.2.7
[1.2.6]: https://github.com/dotsentik/LangSwitcher/releases/tag/v1.2.6
