# Inverso

[English](README.md) | [Русский](README.ru.md)

A menu bar app for macOS that fixes text typed in the wrong keyboard layout. Typed `ghbdtn? rfr ltkf&` instead of `привет, как дела?` — press `⇧⇧` (Shift twice) and the text is converted in place.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/demo-dark.gif">
    <img alt="Typing in the wrong layout, pressing Shift twice and getting the text in Russian, Ukrainian, Spanish, Arabic and Greek" src="docs/demo.gif" width="640">
  </picture>
</p>

Inverso is an unofficial fork of LangSwitcher, see [About this fork](#about-this-fork). Changes: [CHANGELOG.md](CHANGELOG.md). Building, contributing and releasing: [CONTRIBUTING.md](CONTRIBUTING.md).

## Install

1. Download `Inverso-<version>.zip` from [Releases](https://github.com/dotsentik/inverso/releases), unzip it and move `Inverso.app` to `/Applications`.
2. First launch: right-click Inverso → **Open** → **Open**. The app is not notarized by Apple, so a plain double-click is blocked the first time. If macOS says the app is damaged, run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Inverso.app
   ```
3. Grant **Accessibility** access: System Settings → Privacy & Security → Accessibility → turn on Inverso (add it with “+” if it is not listed). Without it the app cannot read or replace text. Settings → Permissions shows the status.

Only the first installation is manual; later versions are installed from the app (see [Updates](#updates)). Every release is signed with the same certificate, so Accessibility access survives updates. If conversion stops working while the switch is on, remove Inverso from the Accessibility list with “−”, add it again and relaunch.

## Usage

1. Type text in any app.
2. Press `⇧⇧`. Selected text is converted; with nothing selected, Smart Conversion takes the text before the cursor.
3. The menu bar icon lets you convert text, switch keyboard layouts, open Settings (`⌘,`) and check for updates.

## Features

- **Converts by physical key position** between any two enabled layouts: `ghbdtn` ↔ `привет`, `руддщ` ↔ `hello`. Character maps are read from the layouts installed in macOS, so any layout works; built-in tables for U.S./ABC/British, Russian, Ukrainian, German, French and Spanish are the fallback.
- **Detects the source layout** from the text. The target is the first layout in your priority order with a different script, or the one you chose for that layout. Afterwards the system layout switches to the target.
- **Punctuation** after a letter converts with the word (`ltkf&` → `дела?`); at the start of a word it stays as typed unless the key gives a letter in the target layout (`;` → `ж`).
- **Smart Conversion** (nothing selected): *Entire Phrase* (default) converts only the wrong-layout part of the line before the cursor, so in `Привет ghbdtn rfr` only `ghbdtn rfr` changes; *Last Word Only*; or *Disabled*.
- **Works in** most apps through the Accessibility API with a `⌘C` / `⌘V` fallback; Electron apps (VS Code, Slack, Discord, Obsidian, Notion…) through the clipboard, which is restored afterwards; Spotlight and Open/Save dialogs.
- **Not supported: terminals** (Terminal, iTerm2, Ghostty, Warp, kitty, Alacritty, WezTerm). The hotkey changes nothing there and the overlay says so.
- **Feedback**: a small overlay at the top of the screen (e.g. `ghbdtn → привет · RU`), or a notification, or nothing; optional sound.

## Settings

Open with `⌘,`.

- **General**: interface language (System, English, Русский), launch at login, update checks, feedback style, sound, Smart Conversion mode.
- **Layouts**: enabled layouts in priority order and the target layout for each.
- **Shortcut**: Double Shift (default) or a custom shortcut.
- **Permissions**: Accessibility status.
- **Log**: off by default; when on, conversions are kept in a local database and can be rated and exported to JSON.

## Updates

Inverso checks for updates once a day with [Sparkle](https://sparkle-project.org) and installs them after you agree; every download is verified with an EdDSA signature. Check manually: menu bar icon → **Check for Updates…**. Automatic checks can be turned off in Settings → General.

If an update fails with “Update Error”, see [Troubleshooting updates](CONTRIBUTING.md#troubleshooting-updates).

## Privacy

No analytics, no telemetry, no accounts. The only network request is the update check (`appcast.xml` from GitHub and, if you agree, the release archive); turn it off and the app makes no requests unless you check manually. The conversion log is off by default and never leaves your Mac.

## Requirements

macOS 15 (Sequoia) or later; Apple Silicon and Intel (universal build); Accessibility permission.

## About this fork

Inverso is an unofficial fork of [LangSwitcher](https://github.com/reg2005/langSwitcher) by LayoutSwitcher Contributors, distributed under the MIT License. The author of the original project is not affiliated with this fork and is not responsible for it; report problems with Inverso here, not to the original project.

Main differences from the original:

- Swift 6 with strict concurrency checking.
- Character maps read from the layouts installed in macOS instead of fixed tables only.
- SwiftUI menu bar menu and Settings window; English and Russian interface.
- Overlay after a conversion instead of notifications.
- Text access through the Accessibility API with a clipboard fallback; Electron apps, Spotlight and Open/Save dialogs.
- Automatic updates through Sparkle.

## License

[MIT](LICENSE)
