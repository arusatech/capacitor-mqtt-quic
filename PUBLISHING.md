# Publishing @annadata/capacitor-mqtt-quic

This guide explains how to publish the plugin to npm for use in mobile apps.

**For a production-grade pack (including native libs under the plugin) and full checklist, use [PRODUCTION_PUBLISH_STEPS.md](./PRODUCTION_PUBLISH_STEPS.md).**

## Prerequisites

- npm account with access to `@annadata` scope
- Node.js 18+
- All native libraries built (see build instructions)

**Note:** The published package includes source code only. Users must build ngtcp2/nghttp3/WolfSSL separately (or use prebuilt libs you ship). You can optionally build and include pre-built libraries (see below).

## Publishing Steps

### 1. Build Native Libraries (Required for iOS)

**iOS podspec requires pre-built libraries in `ios/libs/` and `ios/include/`:**

```bash
# Build for iOS (creates ios/libs/ and ios/include/)
./build-native.sh --ios-only
```

This creates:
- `ios/libs/` - Static libraries (`.a` files) required by podspec
- `ios/include/` - Header files required by podspec

**Note:** Android libraries are built during app compilation via CMake, so they don't need to be pre-built.

### 2. Clean Build Artifacts (Important!)

**Before publishing, clean build artifacts (but KEEP ios/libs/ and ios/include/):**

```bash
npm run clean:build-artifacts
```

This removes:
- `android/build/`, `android/install/`, `android/.gradle/`
- `ios/build/`, `ios/install/`
- **KEEPS:** `ios/libs/`, `ios/include/` (required by podspec)

**Note:** The clean script preserves `ios/libs/` and `ios/include/` because they're needed by the podspec's `vendored_libraries`.

### 3. Build the Plugin

```bash
npm run build
```

This compiles TypeScript and bundles the web implementation.

### 4. Verify Package Contents

**⚠️ IMPORTANT:** Always clean build artifacts before publishing to avoid 502 errors:

```bash
npm run clean:build-artifacts
```

This removes build directories and reduces package size from ~140 MB to ~3 MB.

**Verify the package size:**
```bash
npm pack --dry-run | grep "unpacked size"
```

Should show: `unpacked size: 3.2 MB` (not 140+ MB)

### 4. Verify Package Contents

Check what will be published:

```bash
npm pack --dry-run
```

You should see:
- `dist/` - Compiled TypeScript and bundled web code
- `ios/` - iOS native implementation
  - `ios/libs/` - **Pre-built static libraries** (`.a` files) - REQUIRED
  - `ios/include/` - **Header files** - REQUIRED
  - `ios/Sources/` - Swift source code
- `android/` - Android native implementation (source code only)
- `README.md` - Documentation
- `package.json` - Package metadata

**Verify libraries are included:**
```bash
npm pack --dry-run | grep "ios/libs"
```

Should show files like:
- `ios/libs/libngtcp2.a`
- `ios/libs/libnghttp3.a`
- `ios/libs/libssl.a`
- `ios/libs/libcrypto.a`
- `ios/libs/libngtcp2_crypto_quictls.a`

### 6. Version Bump

Update version in `package.json`:

```json
"version": "0.1.0"  // or "0.1.1", "0.2.0", etc.
```

Or use npm version:

```bash
npm version patch   # 0.1.0 -> 0.1.1
npm version minor   # 0.1.0 -> 0.2.0
npm version major   # 0.1.0 -> 1.0.0
```

### 7. Publish to npm

```bash
npm publish --access public
```

For scoped packages (`@annadata/...`), `--access public` is required unless the scope is configured for private packages.

### 8. Verify Publication

Check npm:

```bash
npm view @annadata/capacitor-mqtt-quic
```

## Using in a Mobile App

After publishing, install in your Capacitor app:

```bash
npm install @annadata/capacitor-mqtt-quic
npx cap sync
```

## Important Notes

### Native Libraries

The published package includes:
- iOS: Swift source + podspec (libraries must be built separately)
- Android: Kotlin source + CMakeLists.txt (libraries must be built separately)

**Users must build ngtcp2/nghttp3/WolfSSL** (or WolfSSL for Android: wolfssl-android) per platform before the plugin works. See:
- `ios/NGTCP2_BUILD_INSTRUCTIONS.md`
- `android/NGTCP2_BUILD_INSTRUCTIONS.md`

### Pre-built Libraries (Optional)

If you want to distribute pre-built libraries:
1. Build for all architectures (iOS: arm64, x86_64; Android: arm64-v8a, armeabi-v7a, x86_64)
2. Include in `ios/libs/` and `android/src/main/jniLibs/<abi>/`
3. Update `.npmignore` to NOT exclude these directories

### CA Certificates

Users should replace placeholder CA PEM files:
- iOS: `ios/Sources/MqttQuicPlugin/Resources/mqttquic_ca.pem`
- Android: `android/src/main/assets/mqttquic_ca.pem`

## Troubleshooting

### 502 Bad Gateway Error

**Symptom:** `npm error 502 Bad Gateway - PUT https://registry.npmjs.org/@annadata%2fcapacitor-mqtt-quic`

**Cause:** Package size is too large (typically 100+ MB unpacked size)

**Solution:**
1. Run `npm run clean:build-artifacts` to remove build artifacts
2. Verify package size: `npm pack --dry-run | grep "unpacked size"` should show ~3 MB
3. Try publishing again: `npm publish --access public`

**Prevention:** The `prepublishOnly` script automatically cleans, but always verify package size before publishing.

### "Package not found" after publish

- Wait a few minutes for npm CDN propagation
- Check scope permissions: `npm whoami`
- Verify package name matches npm registry

### Build fails on user's machine

- Ensure they have Xcode (iOS) or Android Studio (Android)
- Check NDK/CMake versions match requirements
- Verify source dependencies are cloned (`ref-code/ngtcp2`, etc.)

### Native library linking errors

- Users must build ngtcp2/nghttp3/WolfSSL first (Android: wolfssl-android)
- Check `CMakeLists.txt` paths point to correct install directories
- Verify ABI matches device architecture
