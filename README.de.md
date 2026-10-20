# Inverso

[English](README.md) | [Русский](README.ru.md) | [Українська](README.uk.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [हिन्दी](README.hi.md) | [العربية](README.ar.md)

Eine Menüleisten-App für macOS, die Text korrigiert, der mit dem falschen Tastaturlayout getippt wurde. `ghbdtn? rfr ltkf&` statt `привет, как дела?` getippt? Drücken Sie `⇧⇧` (zweimal Shift), und der Text wird an Ort und Stelle umgewandelt.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/demo-dark.gif">
    <img alt="Tippen im falschen Layout, zweimal Shift drücken und den Text auf Russisch, Ukrainisch, Spanisch, Arabisch und Griechisch erhalten" src="docs/demo.gif" width="640">
  </picture>
</p>

Inverso ist ein inoffizieller Fork von LangSwitcher, siehe [Über diesen Fork](#about-this-fork). Änderungen: [CHANGELOG.md](CHANGELOG.md). Bauen, Mitwirken und Veröffentlichen: [CONTRIBUTING.md](CONTRIBUTING.md) (auf Englisch).

> Die Oberfläche der App gibt es auf Englisch und Russisch, daher stehen die Menünamen hier auf Englisch.

## Installation

1. Laden Sie `Inverso-<Version>.zip` von der Seite [Releases](https://github.com/dotsentik/inverso/releases) herunter, entpacken Sie es und verschieben Sie `Inverso.app` nach `/Applications`.
2. Erster Start: Rechtsklick auf Inverso → **Open** → **Open**. Die App ist nicht von Apple notarisiert, deshalb wird ein normaler Doppelklick beim ersten Mal blockiert. Meldet macOS, die App sei beschädigt, führen Sie aus:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Inverso.app
   ```
3. Erteilen Sie den Zugriff **Accessibility**: System Settings → Privacy & Security → Accessibility → Inverso aktivieren (fehlt es in der Liste, mit „+“ hinzufügen). Ohne ihn kann die App Text weder lesen noch ersetzen. Den Status zeigt Settings → Permissions.

Nur die erste Installation erfolgt von Hand; spätere Versionen werden aus der App installiert (siehe [Updates](#updates)). Alle Releases sind mit demselben Zertifikat signiert, daher bleibt der Zugriff nach Updates erhalten. Funktioniert die Umwandlung nicht mehr, obwohl der Schalter aktiv ist, entfernen Sie Inverso mit „−“ aus der Liste, fügen Sie es erneut hinzu und starten Sie die App neu.

## Verwendung

1. Tippen Sie Text in einer beliebigen App.
2. Drücken Sie `⇧⇧`. Markierter Text wird umgewandelt; ist nichts markiert, nimmt die intelligente Umwandlung den Text vor dem Cursor.
3. Über das Symbol in der Menüleiste können Sie Text umwandeln, das Tastaturlayout wechseln, Settings (`⌘,`) öffnen und nach Updates suchen.

## Funktionen

- **Wandelt nach der physischen Tastenposition** zwischen zwei beliebigen aktivierten Layouts um: `ghbdtn` ↔ `привет`, `руддщ` ↔ `hello`. Die Zeichentabellen werden aus den in macOS installierten Layouts gelesen, daher funktioniert jedes Layout; als Ersatz dienen eingebaute Tabellen für U.S./ABC/British, Russisch, Ukrainisch, Deutsch, Französisch und Spanisch.
- **Erkennt das Ausgangslayout** anhand des Textes. Das Ziel ist das erste Layout in Ihrer Prioritätsreihenfolge mit einer anderen Schrift oder das, das Sie für dieses Layout gewählt haben. Anschließend wechselt das System-Layout zum Ziel.
- **Satzzeichen** nach einem Buchstaben werden mit dem Wort umgewandelt (`ltkf&` → `дела?`); am Wortanfang bleiben sie wie getippt, außer die Taste ergibt im Ziellayout einen Buchstaben (`;` → `ж`).
- **Intelligente Umwandlung** (nichts markiert): *Entire Phrase* (Standard) wandelt nur den im falschen Layout getippten Teil der Zeile vor dem Cursor um, in `Привет ghbdtn rfr` ändert sich also nur `ghbdtn rfr`; *Last Word Only*; oder *Disabled*.
- **Wo es funktioniert**: in den meisten Apps über die Accessibility-API mit `⌘C` / `⌘V` als Ausweichlösung; in Electron-Apps (VS Code, Slack, Discord, Obsidian, Notion …) über die Zwischenablage, die danach wiederhergestellt wird; in Spotlight und in Open/Save-Dialogen.
- **Nicht unterstützt: Terminals** (Terminal, iTerm2, Ghostty, Warp, kitty, Alacritty, WezTerm). Das Tastenkürzel bewirkt dort nichts, und das Overlay weist darauf hin.
- **Rückmeldung**: ein kleines Overlay am oberen Bildschirmrand (z. B. `ghbdtn → привет · RU`), eine Mitteilung oder nichts; optional ein Ton.

## Einstellungen

Öffnen mit `⌘,`.

- **General**: Sprache der Oberfläche (System, English, Русский), Start bei der Anmeldung, Update-Suche, Art der Rückmeldung, Ton, Modus der intelligenten Umwandlung.
- **Layouts**: aktivierte Layouts in Prioritätsreihenfolge und das Ziellayout für jedes.
- **Shortcut**: zweimal Shift (Standard) oder ein eigenes Kürzel.
- **Permissions**: Status von Accessibility.
- **Log**: standardmäßig aus; wenn aktiv, werden Umwandlungen in einer lokalen Datenbank gespeichert und können bewertet und als JSON exportiert werden.

<a id="updates"></a>

## Updates

Inverso sucht einmal täglich mit [Sparkle](https://sparkle-project.org) nach Updates und installiert sie nach Ihrer Zustimmung; jeder Download wird mit einer EdDSA-Signatur geprüft. Manuell prüfen: Menüleistensymbol → **Check for Updates…**. Die automatische Suche lässt sich in Settings → General abschalten.

Schlägt ein Update mit „Update Error“ fehl, siehe [Troubleshooting updates](CONTRIBUTING.md#troubleshooting-updates).

## Datenschutz

Keine Analyse, keine Telemetrie, keine Konten. Die einzige Netzwerkanfrage ist die Update-Suche (`appcast.xml` von GitHub und, wenn Sie zustimmen, das Release-Archiv); ist sie abgeschaltet, stellt die App keine Anfragen, solange Sie nicht manuell suchen. Das Umwandlungsprotokoll ist standardmäßig aus und verlässt Ihren Mac nie.

## Voraussetzungen

macOS 15 (Sequoia) oder neuer; Apple Silicon und Intel (Universal-Build); Berechtigung Accessibility.

<a id="about-this-fork"></a>

## Über diesen Fork

Inverso ist ein inoffizieller Fork von [LangSwitcher](https://github.com/reg2005/langSwitcher) von LayoutSwitcher Contributors und steht unter der MIT-Lizenz. Der Autor des ursprünglichen Projekts steht in keiner Verbindung zu diesem Fork und ist nicht dafür verantwortlich; Probleme mit Inverso melden Sie bitte hier, nicht beim ursprünglichen Projekt.

Wichtigste Unterschiede zum Original:

- Swift 6 mit strikter Prüfung der Nebenläufigkeit.
- Zeichentabellen werden aus den in macOS installierten Layouts gelesen, nicht nur aus festen Tabellen.
- Menü in der Menüleiste und Einstellungsfenster in SwiftUI; Oberfläche auf Englisch und Russisch.
- Overlay nach der Umwandlung statt Mitteilungen.
- Textzugriff über die Accessibility-API mit der Zwischenablage als Ausweichlösung; Electron-Apps, Spotlight und Open/Save-Dialoge.
- Automatische Updates über Sparkle.

## Lizenz

[MIT](LICENSE)
