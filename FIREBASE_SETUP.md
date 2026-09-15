# Firebase setup for NOYPON VPN

All Firebase identifiers in this repository are placeholders (`YOUR_PROJECT_ID`,
`YOUR_ANDROID_API_KEY`, …). You must connect your own Firebase project before
building a release. The steps below take ~10 minutes.

## 1. Create the Firebase project

1. Go to https://console.firebase.google.com
2. Click **Add project**, enter a name (e.g. `noypon-vpn`), continue through the
   wizard and enable **Google Analytics** (required for `firebase_analytics`).
3. Inside the new project, add an **Android app**:
   - Package name: `com.noypon.vpn`
   - App nickname: `NOYPON VPN`
   - Download the generated `google-services.json` (you will discard it — step 3
     below will regenerate it automatically).
4. Optionally, add an **iOS app** with bundle id `com.noypon.vpn` if you plan to
   ship to iOS as well.

## 2. Install the FlutterFire CLI

From any shell:

```powershell
dart pub global activate flutterfire_cli
```

Make sure `$HOME/.pub-cache/bin` (or `%LOCALAPPDATA%\Pub\Cache\bin` on Windows)
is on your `PATH`.

## 3. Generate the configuration

From the project root:

```powershell
flutterfire configure --project=<your-project-id>
```

Select the platforms you need (Android, iOS, Web). The CLI will:

- overwrite `lib/firebase_options.dart` with your real keys,
- overwrite `android/app/google-services.json`,
- overwrite `ios/Runner/GoogleService-Info.plist`,
- regenerate `firebase.json` at the repository root.

## 4. Enable Crashlytics & Analytics

In the Firebase console:

1. **Crashlytics → Get started** for the Android app.
2. **Analytics → Events** — verify events start appearing once you run the app.

No additional code changes are required; initialisation is already wired up in
`lib/main.dart`.

## 5. Notes

- The APK build will still compile even if Firebase is not configured, but the
  Firebase SDK will throw at runtime on `Firebase.initializeApp`. The VPN
  functionality itself does not depend on Firebase.
- If you rotate keys or change project id, re-run `flutterfire configure`.
- Never commit real `google-services.json` / `GoogleService-Info.plist` to a
  public repo; `.gitignore` already excludes `key.properties` and keystore
  files, but Firebase config files are intentionally kept tracked so fresh
  clones can build immediately after `flutterfire configure`.
