# Inverso

[English](README.md) | [Русский](README.ru.md) | [Українська](README.uk.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [हिन्दी](README.hi.md) | [العربية](README.ar.md)

Una app de la barra de menús de macOS que corrige el texto escrito con la distribución de teclado equivocada. ¿Escribiste `ma;ana` en lugar de `mañana`, o `ghbdtn? rfr ltkf&` en lugar de `привет, как дела?`? Pulsa `⇧⇧` (Mayús dos veces) y el texto se convierte en el sitio.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/demo-dark.gif">
    <img alt="Escribir con la distribución equivocada, pulsar Mayús dos veces y obtener el texto en ruso, ucraniano, español, árabe y griego" src="docs/demo.gif" width="640">
  </picture>
</p>

Inverso es un fork no oficial de LangSwitcher, véase [Acerca de este fork](#about-this-fork). Cambios: [CHANGELOG.md](CHANGELOG.md). Compilación, contribuciones y publicación de versiones: [CONTRIBUTING.md](CONTRIBUTING.md) (en inglés).

> La interfaz de la app está disponible en inglés y ruso, por eso los nombres de los menús se dan aquí en inglés.

## Instalación

1. Descarga `Inverso-<versión>.zip` desde [Releases](https://github.com/dotsentik/inverso/releases), descomprímelo y mueve `Inverso.app` a `/Applications`.
2. Primer arranque: clic derecho sobre Inverso → **Open** → **Open**. Apple no ha notarizado la app, así que el doble clic normal se bloquea la primera vez. Si macOS dice que la app está dañada, ejecuta:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Inverso.app
   ```
3. Concede el acceso de **Accessibility**: System Settings → Privacy & Security → Accessibility → activa Inverso (si no aparece en la lista, añádelo con «+»). Sin él la app no puede leer ni sustituir texto. El estado se ve en Settings → Permissions.

Solo la primera instalación es manual; las siguientes versiones se instalan desde la app (véase [Actualizaciones](#updates)). Todas las versiones se firman con el mismo certificado, así que el acceso sobrevive a las actualizaciones. Si la conversión deja de funcionar aunque el interruptor esté activado, quita Inverso de la lista con «−», añádelo de nuevo y reinicia la app.

## Uso

1. Escribe texto en cualquier app.
2. Pulsa `⇧⇧`. El texto seleccionado se convierte; si no hay nada seleccionado, la conversión inteligente toma el texto anterior al cursor.
3. El icono de la barra de menús permite convertir texto, cambiar de distribución de teclado, abrir Settings (`⌘,`) y buscar actualizaciones.

## Funciones

- **Convierte por posición física de las teclas** entre dos distribuciones activadas cualesquiera: `ghbdtn` ↔ `привет`, `руддщ` ↔ `hello`. Los mapas de caracteres se leen de las distribuciones instaladas en macOS, por lo que sirve cualquiera; como respaldo hay tablas integradas para U.S./ABC/British, ruso, ucraniano, alemán, francés y español.
- **Detecta la distribución de origen** a partir del texto. El destino es la primera distribución de tu orden de prioridad con otro alfabeto, o la que elijas para esa distribución. Después la distribución del sistema cambia a la de destino.
- **La puntuación** tras una letra se convierte con la palabra (`ltkf&` → `дела?`); al comienzo de una palabra se queda como se escribió, salvo que la tecla dé una letra en la distribución de destino (`;` → `ж`).
- **Conversión inteligente** (sin selección): *Entire Phrase* (por defecto) convierte solo la parte de la línea anterior al cursor escrita con la distribución equivocada, así que en `Привет ghbdtn rfr` solo cambia `ghbdtn rfr`; *Last Word Only*; o *Disabled*.
- **Dónde funciona**: en la mayoría de las apps mediante la API de Accessibility con `⌘C` / `⌘V` como alternativa; en apps Electron (VS Code, Slack, Discord, Obsidian, Notion…) mediante el portapapeles, que luego se restaura; en Spotlight y en los diálogos Open/Save.
- **No se admiten los terminales** (Terminal, iTerm2, Ghostty, Warp, kitty, Alacritty, WezTerm): la tecla rápida no cambia nada allí y la superposición lo indica.
- **Aviso**: una pequeña superposición en la parte superior de la pantalla (por ejemplo, `ghbdtn → привет · RU`), una notificación o nada; sonido opcional.

## Ajustes

Se abren con `⌘,`.

- **General**: idioma de la interfaz (System, English, Русский), abrir al iniciar sesión, búsqueda de actualizaciones, tipo de aviso, sonido, modo de conversión inteligente.
- **Layouts**: distribuciones activadas por orden de prioridad y la distribución de destino de cada una.
- **Shortcut**: doble Mayús (por defecto) o un atajo propio.
- **Permissions**: estado de Accessibility.
- **Log**: desactivado por defecto; si se activa, las conversiones se guardan en una base de datos local, se pueden valorar y exportar a JSON.

<a id="updates"></a>

## Actualizaciones

Inverso busca actualizaciones una vez al día con [Sparkle](https://sparkle-project.org) y las instala cuando lo aceptas; cada descarga se verifica con una firma EdDSA. Búsqueda manual: icono de la barra de menús → **Check for Updates…**. La búsqueda automática se puede desactivar en Settings → General.

Si una actualización falla con «Update Error», consulta [Troubleshooting updates](CONTRIBUTING.md#troubleshooting-updates).

## Privacidad

Sin analíticas, sin telemetría, sin cuentas. La única petición de red es la búsqueda de actualizaciones (`appcast.xml` de GitHub y, si aceptas, el archivo de la versión); si la desactivas, la app no hace peticiones mientras no busques actualizaciones a mano. El registro de conversiones está desactivado por defecto y nunca sale de tu Mac.

## Requisitos

macOS 15 (Sequoia) o posterior; Apple Silicon e Intel (compilación universal); permiso de Accessibility.

<a id="about-this-fork"></a>

## Acerca de este fork

Inverso es un fork no oficial de [LangSwitcher](https://github.com/reg2005/langSwitcher) de LayoutSwitcher Contributors, distribuido bajo la licencia MIT. El autor del proyecto original no está vinculado a este fork ni es responsable de él; informa de los problemas de Inverso aquí, no en el proyecto original.

Diferencias principales con el original:

- Swift 6 con comprobación estricta de concurrencia.
- Mapas de caracteres leídos de las distribuciones instaladas en macOS, y no solo de tablas fijas.
- Menú de la barra de menús y ventana de ajustes en SwiftUI; interfaz en inglés y ruso.
- Superposición tras la conversión en lugar de notificaciones.
- Acceso al texto mediante la API de Accessibility con el portapapeles como alternativa; apps Electron, Spotlight y diálogos Open/Save.
- Actualizaciones automáticas mediante Sparkle.

## Licencia

[MIT](LICENSE)
