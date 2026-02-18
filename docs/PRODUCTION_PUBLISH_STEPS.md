# Production publish steps – @annadata/capacitor-mqtt-quic

This checklist makes the plugin **production-grade**: pack everything needed (including native libs under the plugin), then publish to npm so consumers can use it with no app-side workarounds.

**Production readiness** (Options 1+2+4) is already in place; see [CAPACITOR_MQTT_QUIC_PRODUCTION_PLUGIN.md](./CAPACITOR_MQTT_QUIC_PRODUCTION_PLUGIN.md). Follow the steps below to build, pack, and publish.

---

## Prerequisites

- Node.js 18+
- **iOS:** macOS, Xcode 14+
- **Android:** Android Studio, NDK r25+ (e.g. via `$ANDROID_HOME/ndk/<version>`)
- npm account with access to `@annadata` scope

---

## Step 1: Build native libraries (required for packaging)

Build **iOS** and **Android** native deps so they are included in the package.

### iOS (required for podspec)

```bash
./build-native.sh --ios-only
```

This produces:

- `ios/libs/` – static libs (e.g. `libngtcp2.a`, `libngtcp2_crypto_wolfssl.a`, `libnghttp3.a`, `libwolfssl.a`)
- `ios/include/` – headers

The podspec’s `vendored_libraries` point at `ios/libs/`; these **must** be present when you pack/publish.

### Android (required for zero-config / “complete” package)

Android uses **WolfSSL** (same TLS backend as iOS). To ship a **complete** plugin so clients don’t run any native build, build WolfSSL + nghttp3 + ngtcp2 for all ABIs:

```bash
npm run build:android-prebuilts
```

Or manually:

```bash
./build-native.sh --android-only --abi arm64-v8a
./build-native.sh --android-only --abi armeabi-v7a
./build-native.sh --android-only --abi x86_64
```

This populates `android/install/wolfssl-android/<abi>/`, `android/install/nghttp3-android/<abi>/`, and `android/install/ngtcp2-android/<abi>/`. The plugin’s `clean:build-artifacts` script **does not** remove `android/install`, so these will be included in the tarball when present.

---

## Step 2: Clean build artifacts (keeps libs)

```bash
npm run clean:build-artifacts
```

This removes only:

- `android/build/`, `android/.gradle/`
- `ios/build/`, `ios/install/`

It **keeps**:

- `ios/libs/`, `ios/include/` (required by podspec)
- `android/install/` (prebuilt WolfSSL/wolfssl-android when you built it in Step 1)

---

## Step 3: Build the plugin (TypeScript + bundle)

```bash
npm run build
```

---

## Step 4: Verify package contents

```bash
npm pack --dry-run
```

Check:

- `dist/` – JS/TS build
- `ios/` – including `ios/libs/*.a`, `ios/include/`
- `android/` – including `android/install/` if you built WolfSSL (wolfssl-android)
- `deps-versions.sh`, `build-native.sh` – for consumers who need to rebuild
- `docs/` – includes this checklist and other docs (e.g. `docs/PRODUCTION_PUBLISH_STEPS.md`, `docs/PROJECT_OVERVIEW.md`)
- `AnnadataCapacitorMqttQuic.podspec`, `README.md`

Optional size check:

```bash
npm pack --dry-run | grep "unpacked size"
```

With prebuilt iOS + Android libs the package will be larger (tens of MB); without Android prebuilts it stays smaller.

---

## Step 5: Bump version

```bash
npm version patch   # 0.1.6 → 0.1.7
# or
npm version minor   # 0.1.6 → 0.2.0
```

Or edit `version` in `package.json` manually.

---

## Step 6: Publish to npm

```bash
npm publish --access public
```

Scoped packages (`@annadata/...`) need `--access public` unless the scope is private.

---

## Step 7: Verify

```bash
npm view @annadata/capacitor-mqtt-quic
```

---

## Summary: what gets packed

| Item | When it’s included |
|------|--------------------|
| `dist/` | Always (from `npm run build`) |
| `ios/`, `android/` | Always (listed in `package.json` `files`) |
| `ios/libs/`, `ios/include/` | When present; **not** removed by `clean:build-artifacts` |
| `android/install/` | When present (after Android WolfSSL/ngtcp2 build); **not** removed by clean |
| `deps-versions.sh`, `build-native.sh` | Always (in `files`) |
| `docs/` | Always (in `files`; includes this checklist and PROJECT_OVERVIEW) |
| `AnnadataCapacitorMqttQuic.podspec`, `README.md` | Always |
| CA cert bundle (optional) | `ios/.../Resources/mqttquic_ca.pem`, `android/.../assets/mqttquic_ca.pem` — packed with `ios/` and `android/`; used for QUIC TLS verification unless overridden by `caFile`/`caPath` |

`.npmignore` is set so that `ios/libs/`, `ios/include/`, and `android/install/` are **not** excluded when present. Certificate files (`.pem`) under `ios/` and `android/` are **included** in the package.

---

## Consumer experience after publish

- **With prebuilt libs (iOS + Android):**  
  `npm install @annadata/capacitor-mqtt-quic` → `npx cap sync` → build app. No extra steps.

- **With only iOS prebuilts:**  
  Same for iOS. For Android, consumers run the one-time WolfSSL/ngtcp2 build steps documented in the plugin README (Production / First-time build), e.g. `./build-native.sh --android-only --abi arm64-v8a` (and other ABIs).

---

## Troubleshooting

- **502 on publish:** Package too large. Run `npm run clean:build-artifacts` and ensure you’re not including huge `deps/` or `ref-code/` (they should be gitignored and not in `files`).
- **“WolfSSL not found” on consumer Android build:** They need the one-time WolfSSL/ngtcp2 build (see README), or you need to ship `android/install/` (Step 1).
- **iOS pod install fails:** Ensure `ios/libs/` and `ios/include/` are present in the tarball (`npm pack && tar -tf *.tgz | grep ios/libs`).
