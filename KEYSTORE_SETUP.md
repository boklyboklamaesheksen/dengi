# Android release signing for NOYPON VPN

Debug builds work out of the box. For a release build (AAB/APK) you need your
own keystore.

## 1. Generate an upload keystore

From the `android/` folder:

```powershell
keytool -genkey -v `
  -keystore upload-keystore.jks `
  -alias upload `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000
```

Answer the prompts (organisation, name, etc.) and **remember** the store /
key passwords.

Move the resulting `upload-keystore.jks` to `android/app/upload-keystore.jks`
(it is already covered by `android/.gitignore`).

## 2. Create `android/key.properties`

Copy the template and fill in your values:

```
storeFile=upload-keystore.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=upload
keyPassword=YOUR_KEY_PASSWORD
```

A template is provided at `android/key.properties.example`.

## 3. Build the release

```powershell
flutter build appbundle --release
```

The Gradle build reads `android/key.properties` and signs the AAB with your
keystore. If `key.properties` is absent, the build falls back to debug signing
(so CI / fresh clones never fail) but the resulting artifact is NOT
distributable on Google Play.

## Important

- Back up your keystore **and** passwords. Losing them means you can never
  publish an update for the same package name on Google Play.
- Do not commit `key.properties` or `*.jks` to version control.
