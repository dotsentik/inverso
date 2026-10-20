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

## Migrating from LangSwitcher

Inverso was called LangSwitcher up to version 1.2.6. The bundle identifier changed
(`com.dotsentik.inverso`), so LangSwitcher builds cannot update to Inverso through
Sparkle. To test or use Inverso on a Mac with LangSwitcher:

1. Quit LangSwitcher and delete the old copy from `/Applications`.
2. Remove LangSwitcher from System Settings → Privacy & Security → Accessibility (“−”).
3. Install Inverso manually from the GitHub Release.
4. Grant Inverso Accessibility access.
5. Optional: copy the old log, `~/Library/Application Support/LangSwitcher/conversion_log.sqlite`,
   to `~/Library/Application Support/Inverso/`. Inverso copies it by itself on the first
   launch if its own directory does not exist yet.

## Never commit

`dist/`, `build/`, keys and certificates (`.p12`, `.pem`, `.key`, `.cer`), logs, `*.zip`,
`*.dmg`, `*.profraw`.
