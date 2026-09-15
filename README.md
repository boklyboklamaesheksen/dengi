# Rabochiy VPN

Premium Flutter VPN client with a **Stark Mono** UI (xAI-style dark theme:
near-black `#1F2228` canvas, pure white accents, monospace display type).
Tunnels run through AmneziaWG and the GW SSH/socks engine, with the
server list pulled from the backend API. The Russian product name is
**Рабочий VPN**; the English name remains **Rabochiy VPN**.

## Features

- One-tap connect / disconnect with animated power dial
- Automatic server selection based on backend recommendations and load
- Manual bottom-sheet server picker with search + per-node load bar
- Live download / upload sparklines while the tunnel is up
- Split tunneling (per-app allow/block list)
- 14 interface languages: EN, RU, FR, NL, DE, ES, IT, PL, PT-PT, RO, SV,
  DA, FI, CS, including privacy documents and VPN notifications
- Dark-mode design; Firebase Crashlytics, Analytics and Remote Config
  (see the in-app privacy policy and `FIREBASE_SETUP.md`)

## Android build

- Package / application id: `app.rabochiy.vpn`
- Version: `1.0.1` (build 3), following published Android `1.0.0 (2)`.
  `pubspec.yaml` is the source of truth; Android and Settings read it via
  Flutter build metadata and `PackageInfo`, respectively.
- Android: API 24+, target/compile SDK 36, JDK 17, AGP 8.13.2
- Flutter SDK must include Dart 3.10.8 or newer, compatible with `pubspec.yaml`
- Signing: `android/key.properties` (see `KEYSTORE_SETUP.md`)
- Firebase: `android/app/google-services.json` (see `FIREBASE_SETUP.md`)

Before running or building, copy `config/build-secrets.example.json` to
`config/build-secrets.json` and fill `RABOCHIY_SIGNING_SECRET` with the
backend's configured signing value. The local file is ignored by Git.
Without it, legacy signed API requests fail; do not publish such a build.
Never put real values in the example file or commit a keystore.

The upstream source exposed a signing value: rotate it with the backend
operator, coordinating compatibility with installed clients. Moving it to
a Dart define prevents committing it, but **does not hide it from an APK**;
client-side shared secrets are not a substitute for server authentication.

```bash
flutter pub get
flutter run --dart-define-from-file=config/build-secrets.json
# Release command for the maintainer; no app build was run for this change:
flutter build appbundle --release --obfuscate \
  --split-debug-info=build/symbols/1.0.1-3 \
  --dart-define-from-file=config/build-secrets.json
```

Archive the Dart symbols, R8 mapping and matching native symbols privately
for each release. Do not publish the AAB before the release checklist in
[`docs/RELEASE_1_0_1.md`](docs/RELEASE_1_0_1.md) is complete.

## Localisation and store copy

EU source messages are `lib/l10n/catalogs/*.json`; privacy documents are
`lib/l10n/policies/*.txt`. EN/RU remain hand-written Dart catalogues.
Regenerate EU Dart messages and native notifications after editing:

```bash
python3 tools/generate_localizations.py
python3 tools/generate_localizations.py --check
python3 tools/check_release_metadata.py
```

`eupage.txt` contains 12 EU store listings and 14 release-note blocks.
Country-specific positioning and its limits are documented in
[`docs/EU_MARKET_RESEARCH.md`](docs/EU_MARKET_RESEARCH.md). Existing EN/RU
store descriptions supplied in `page.txt` are not replaced.

## Project layout

```
lib/            Flutter app (screens, widgets, motion, services, l10n)
android/        Android host and AmneziaWG/GW native modules
assets/images/  Launcher icon art (logo_rabochiy*.png)
tool/, tools/   Icon scripts, localisation generator and metadata checks
docs/           Market research and release verification checklist
```
