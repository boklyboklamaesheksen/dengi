# Rabochiy VPN

Premium Flutter VPN client with a **Stark Mono** UI (xAI-style dark theme:
near-black `#1F2228` canvas, pure white accents, monospace display type).
Tunnels run through native engines — IKEv2 (vendored StrongSwan sources +
JNI libs) and AmneziaWG (userspace GoBackend + `libwg-go.so`) — with the
server list pulled from the backend API.

## Features

- One-tap connect / disconnect with animated power dial
- Automatic selection of the lowest-latency server
- Manual bottom-sheet server picker with search + per-node load bar
- Live download / upload sparklines while the tunnel is up
- Split tunneling (per-app allow/block list)
- Bilingual interface (EN / RU) — hand-written localisations in `lib/l10n/`
- Fully dark-mode design, no ads, no telemetry beyond optional Firebase
  Crashlytics

## Android build

- Package / application id: `app.rabochiy.vpn`
- Version: `1.0.0` (build 1) — see `pubspec.yaml` and
  `android/app/build.gradle.kts`
- Signing: `android/key.properties` (see `KEYSTORE_SETUP.md`)
- Firebase: `android/app/google-services.json` (see `FIREBASE_SETUP.md`)

```bash
flutter pub get
flutter run            # debug
flutter build apk      # release APK
```

## Project layout

```
lib/            Flutter app (screens, widgets, motion, services, l10n)
android/        Android host: app module + amneziawg-tunnel module
assets/images/  Launcher icon art (logo_rabochiy*.png)
tool/, tools/   One-off icon generation scripts (Pillow / PowerShell)
```
