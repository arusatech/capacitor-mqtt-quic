# Making @annadata/capacitor-mqtt-quic a Production-Ready Plugin

This document describes how the **capacitor-mqtt-quic** plugin is made production-ready so that **anyone can use it directly** (`npm install @annadata/capacitor-mqtt-quic`) and build Android/iOS **without app-side workarounds**.

---

## Start here: Publish a production plugin

**This plugin is production-ready** when Options 1, 2, and 4 below are in place (they are). To **generate and publish** the production plugin, follow the step-by-step checklist:

- **[docs/PRODUCTION_PUBLISH_STEPS.md](./PRODUCTION_PUBLISH_STEPS.md)** — Build native libs, clean, build JS, verify package, bump version, publish to npm.

After publishing, consumers can `npm install @annadata/capacitor-mqtt-quic` and follow the README’s **Production / First-time build** section if they need to run the one-time WolfSSL/ngtcp2 build for Android.

---

## Current Situation

- **Development:** Apps (e.g. annadata-app, test16) may work around the plugin by providing `deps-versions.sh` (pinned WolfSSL/ngtcp2 versions) and/or running setup scripts.
- **Production / direct use:** A consumer who only runs `npm install` and `ionic cap run android` may hit:
  - **Android:** CMake fails with "WolfSSL not found" if `android/install/wolfssl-android` (and ngtcp2/nghttp3 installs) are not shipped. Run the one-time `./build-native.sh --android-only` (or ship prebuilts).

---

## TLS backend: WolfSSL on both iOS and Android

**iOS** and **Android** both use **WolfSSL** as the only TLS backend (license/size/QUIC support):

- **iOS:** Podspec ships `libngtcp2_crypto_wolfssl.a` and `libwolfssl.a`; `NGTCP2Bridge.mm` uses `wolfSSL_*` APIs only.
- **Android:** `android/src/main/cpp/CMakeLists.txt` finds and links WolfSSL (`libwolfssl.a`) and `libngtcp2_crypto_wolfssl.a`. `ngtcp2_jni.cpp` uses `ngtcp2_crypto_wolfssl.h` and `<wolfssl/ssl.h>` (same as iOS).

For the **Android build** you need **WolfSSL** (and nghttp3, ngtcp2 built with WolfSSL) in `android/install/wolfssl-android/<abi>/`, etc. One-time setup: `./build-native.sh --android-only --abi <abi>` (or the individual `build-wolfssl.sh`, `build-nghttp3.sh`, `build-ngtcp2.sh` scripts).

---

## Process to Make the Plugin Complete (Production Setup)

Choose **one** of the approaches below (or combine 1 + 2 for best UX).

---

### Option 1: Ship `deps-versions.sh` in the Plugin (Recommended minimum)

**Goal:** One-time run of the plugin’s own `build-openssl.sh` works without the app providing any file.

**Steps:**

1. **Add `deps-versions.sh` in the plugin repo** (e.g. at repo root, next to `package.json`), with a **pinned QuicTLS commit** that still has the Perl `Configure` script:

   ```bash
   # deps-versions.sh (in plugin root)
   export QUICTLS_REPO_URL="${QUICTLS_REPO_URL:-https://github.com/quictls/quictls.git}"
   export OPENSSL_COMMIT="${OPENSSL_COMMIT:-2cc13b7c86fd76e5b45b5faa4ca365a602f92392}"

   export NGHTTP3_REPO_URL="${NGHTTP3_REPO_URL:-https://github.com/ngtcp2/nghttp3.git}"
   export NGHTTP3_COMMIT="${NGHTTP3_COMMIT:-78f27c1}"
   export NGTCP2_REPO_URL="${NGTCP2_REPO_URL:-https://github.com/ngtcp2/ngtcp2.git}"
   export NGTCP2_COMMIT="${NGTCP2_COMMIT:-3ce3bbead}"
   ```

2. **Include it in the published package:** in `package.json` add `"deps-versions.sh"` to the `files` array:

   ```json
   "files": ["dist", "ios", "android", "deps-versions.sh", "AnnadataCapacitorMqttQuic.podspec", "README.md"]
   ```

3. **Document one-time setup** in the plugin README (see “Consumer instructions” below).

**Result:** Consumers run the plugin’s `build-openssl.sh` once (or your documented script); it sources `deps-versions.sh` from the plugin and uses `OPENSSL_COMMIT`, so the clone has `Configure` and the build succeeds. No app-side keys or copy steps.

---

### Option 2: Change Default Branch in `build-openssl.sh`

**Goal:** Even without `deps-versions.sh`, cloning QuicTLS works (branch still has `Configure`).

**Steps:**

1. In **`android/build-openssl.sh`** (and iOS if applicable), change the default branch from `main` to a branch that still has the Perl Configure script, e.g.:

   ```bash
   QUICTLS_BRANCH="${QUICTLS_BRANCH:-openssl-3.2}"
   ```

   (Use the same in iOS `build-openssl.sh` if it uses QuicTLS.)

2. Optionally still ship **Option 1** so that when `deps-versions.sh` is present, pinned commit takes precedence for reproducible builds.

**Result:** If the consumer doesn’t have `deps-versions.sh`, the script still clones a branch that has `Configure` and builds.

---

### Option 3: Ship Prebuilt WolfSSL (wolfssl-android) in the npm Package (Zero-config)

**Goal:** `npm install` + `ionic cap run android` works with **no** run of `build-wolfssl.sh`.

**Steps:**

1. **Build WolfSSL (wolfssl-android) once per ABI** using the plugin’s `build-wolfssl.sh` (or `./build-native.sh --android-only --abi <abi>`), for:
   - `arm64-v8a`, `armeabi-v7a`, `x86_64` (and `x86` if you support it).

2. **Keep the artifacts** under:
   - `android/install/wolfssl-android/arm64-v8a/`
   - `android/install/wolfssl-android/armeabi-v7a/`
   - `android/install/wolfssl-android/x86_64/`
   (each with `include/` and `lib/libwolfssl.a`). Also build nghttp3 and ngtcp2 so `android/install/nghttp3-android/<abi>/` and `android/install/ngtcp2-android/<abi>/` exist.

3. **Include them in the published package:**
   - Do **not** remove `android/install` in `clean:build-artifacts` (so prepack/prepublishOnly do not delete it).
   - `android` is already in the `files` array, so `android/install/` is published when present.

4. **iOS:** Ship prebuilt libs in `ios/libs/` and `ios/include/` (built with `./build-native.sh --ios-only`); the clean script already keeps these.

**Result:** Consumers get WolfSSL (wolfssl-android) and ngtcp2/nghttp3 with the plugin; Gradle/CMake find them and the app builds without any one-time setup. Trade-off: larger npm package size.

---

### Option 4: Clear Docs and Build-Time Message

**Goal:** When something is missing, the failure is clear and points to a single place.

**Steps:**

1. **README:** Add a short “Production / first-time build” section:
   - **Android:** Before first `ionic cap run android`, run once (from project root):
     ```bash
     cd node_modules/@annadata/capacitor-mqtt-quic && \
       ./build-native.sh --android-only --abi arm64-v8a && \
       ./build-native.sh --android-only --abi armeabi-v7a && \
       ./build-native.sh --android-only --abi x86_64
     ```
   - Or add an npm script in your app that runs the above.
   - Require Android NDK (r25+).

2. **Optional:** In the plugin’s Android CMake or Gradle, if WolfSSL is not found, fail with a message that points to the README (e.g. “WolfSSL not found. Run the one-time setup: …” and link to the plugin README).

**Result:** No change to plugin code, but production users have a single, clear path and no guesswork.

---

## Recommended Combination for Production

- **Do Option 1 + Option 2:**  
  - Ship `deps-versions.sh` in the plugin and add it to `files`.  
  - Default `QUICTLS_BRANCH` in `build-openssl.sh` to `openssl-3.2` (or another branch that has `Configure`).  
  This gives reproducible builds when the file is used, and a working default when it is not.

- **Do Option 4** in the plugin README so every consumer sees the one-time Android (and iOS if needed) setup.

- **Option 3** is optional: only if you want true zero-config and accept a larger package.

---

## Consumer Instructions (for Plugin README)

After the above are done, the plugin README can say:

**Android (one-time setup)**  
Before the first Android build, build WolfSSL (wolfssl-android) and ngtcp2/nghttp3 once. From your project root:

```bash
cd node_modules/@annadata/capacitor-mqtt-quic
./build-native.sh --android-only --abi arm64-v8a
./build-native.sh --android-only --abi armeabi-v7a
./build-native.sh --android-only --abi x86_64
```

Or add to your app’s `package.json`:

```json
"setup:wolfssl-android": "cd node_modules/@annadata/capacitor-mqtt-quic && ./build-native.sh --android-only --abi arm64-v8a && ./build-native.sh --android-only --abi armeabi-v7a && ./build-native.sh --android-only --abi x86_64"
```

Then run `npm run setup:wolfssl-android` once. Requires Android NDK (r25+).

**iOS**  
(If applicable, add the corresponding one-time build steps for iOS here.)

---

## Summary

| Approach | Effort | Result |
|----------|--------|--------|
| **1. Ship deps-versions.sh** | Low | One-time `build-native.sh` (or build-wolfssl.sh) works without app providing keys. |
| **2. Default branch openssl-3.2** | Low | Clone works even without deps-versions.sh. |
| **3. Ship prebuilt WolfSSL (wolfssl-android)** | Medium (build + package size) | No WolfSSL one-time step for consumers. |
| **4. README + clear failure message** | Low | Direct use is documented and failures are understandable. |

Making the **complete** production plugin means: at least **1 + 2 + 4** so that anyone who installs the plugin and follows the README can build without app-side workarounds.
