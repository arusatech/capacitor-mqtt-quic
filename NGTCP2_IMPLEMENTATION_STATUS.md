# ngtcp2 Integration Implementation Status

This document tracks the implementation progress of ngtcp2 integration for the Capacitor MQTT-over-QUIC plugin.

## Overview

The ngtcp2 integration replaces the stub QUIC implementations (`QuicClientStub`) with real QUIC transport using the ngtcp2 library. This enables actual MQTT-over-QUIC connections on iOS and Android.

## Implementation Status

### Phase 1: iOS Implementation ✅ Structure Complete

**Status:** Foundation and structure created, ready for ngtcp2 library integration

**Completed:**
- ✅ `NGTCP2Client.swift` - Swift wrapper implementing `QuicClientProtocol`
- ✅ Build scripts (`build-ngtcp2.sh`, `build-openssl.sh`)
- ✅ Build documentation (`NGTCP2_BUILD_INSTRUCTIONS.md`)
- ✅ Error handling and connection state management
- ✅ Stream management infrastructure

**Remaining:**
- ⏳ Build ngtcp2 static library for iOS
- ⏳ Build OpenSSL for iOS (or use pre-built)
- ⏳ Implement ngtcp2 C API calls in `NGTCP2Client.swift`
- ⏳ Implement TLS 1.3 handshake
- ⏳ Implement UDP packet send/receive handlers
- ⏳ Integrate into Xcode project (update podspec)

**Files Created:**
- `ios/Sources/MqttQuicPlugin/QUIC/NGTCP2Client.swift`
- `ios/build-ngtcp2.sh`
- `ios/build-openssl.sh`
- `ios/NGTCP2_BUILD_INSTRUCTIONS.md`

### Phase 2: Android Implementation ✅ Structure Complete

**Status:** Foundation and structure created, ready for ngtcp2 library integration

**Completed:**
- ✅ `NGTCP2Client.kt` - Kotlin wrapper implementing `QuicClient` interface
- ✅ `ngtcp2_jni.cpp` - JNI bridge between Kotlin and ngtcp2
- ✅ `CMakeLists.txt` - Build configuration for native library
- ✅ Build scripts (`build-ngtcp2.sh`, `build-openssl.sh`)
- ✅ Build documentation (`NGTCP2_BUILD_INSTRUCTIONS.md`)

**Remaining:**
- ⏳ Build ngtcp2 native library for Android
- ⏳ Build OpenSSL for Android (or use pre-built)
- ⏳ Implement ngtcp2 C API calls in `ngtcp2_jni.cpp`
- ⏳ Implement TLS 1.3 handshake
- ⏳ Implement UDP packet send/receive handlers
- ⏳ Integrate into Android project (update build.gradle)

**Files Created:**
- `android/src/main/kotlin/ai/annadata/mqttquic/quic/NGTCP2Client.kt`
- `android/src/main/cpp/ngtcp2_jni.cpp`
- `android/src/main/cpp/CMakeLists.txt`
- `android/build-ngtcp2.sh`
- `android/build-openssl.sh`
- `android/NGTCP2_BUILD_INSTRUCTIONS.md`

### Phase 3: Replace Stubs ⏳ Pending

**Status:** Not started - waiting for Phase 1 and 2 completion

**Tasks:**
- Replace `QuicClientStub` with `NGTCP2Client` in `MQTTClient.swift` (iOS)
- Replace `QuicClientStub` with `NGTCP2Client` in `MQTTClient.kt` (Android)
- Update error handling for real network errors
- Test connection establishment

### Phase 4: Testing ⏳ Pending

**Status:** Not started - waiting for Phase 3 completion

**Tasks:**
- Unit tests for ngtcp2 integration
- Integration tests against MQTT server
- Performance testing
- Error scenario testing

### Phase 5: Documentation ⏳ Pending

**Status:** Not started - waiting for Phase 4 completion

**Tasks:**
- Update README.md with build instructions
- Document ngtcp2 integration details
- Add troubleshooting guide
- Document TLS certificate requirements

## Next Steps

### Immediate (Before Building ngtcp2)

1. **Obtain ngtcp2 Source:**
   ```bash
   git clone https://github.com/ngtcp2/ngtcp2.git
   ```

2. **Obtain OpenSSL Source (if building from source):**
   ```bash
   git clone https://github.com/openssl/openssl.git
   ```

### iOS Build Process

1. **Build OpenSSL for iOS:**
   ```bash
   cd ref-code/capacitor-mqtt-quic/ios
   ./build-openssl.sh --arch arm64 --sdk iphoneos
   ```

2. **Build ngtcp2 for iOS:**
   ```bash
   ./build-ngtcp2.sh \
     --openssl-path ./install/openssl-ios \
     --arch arm64 \
     --sdk iphoneos
   ```

3. **Update `NGTCP2Client.swift`:**
   - Uncomment and implement ngtcp2 C API calls
   - Implement TLS 1.3 handshake
   - Implement UDP packet handlers

4. **Update `MqttQuicPlugin.podspec`:**
   - Add ngtcp2 library linking
   - Add header search paths

### Android Build Process

1. **Build OpenSSL for Android:**
   ```bash
   cd ref-code/capacitor-mqtt-quic/android
   ./build-openssl.sh \
     --ndk-path ~/Android/Sdk/ndk/25.2.9519653 \
     --abi arm64-v8a \
     --platform android-21
   ```

2. **Build ngtcp2 for Android:**
   ```bash
   ./build-ngtcp2.sh \
     --ndk-path ~/Android/Sdk/ndk/25.2.9519653 \
     --abi arm64-v8a \
     --platform android-21 \
     --openssl-path ./install/openssl-android
   ```

3. **Update `ngtcp2_jni.cpp`:**
   - Uncomment and implement ngtcp2 C API calls
   - Implement TLS 1.3 handshake
   - Implement UDP packet handlers

4. **Update `build.gradle`:**
   - Configure CMake build
   - Link ngtcp2 libraries

## Key Implementation Notes

### iOS Implementation

- Uses **Network framework** (`NWConnection`) for UDP
- Uses **Swift async/await** for asynchronous operations
- ngtcp2 C functions called via Swift C interop
- TLS 1.3 via OpenSSL/BoringSSL

### Android Implementation

- Uses **DatagramSocket** for UDP
- Uses **Kotlin coroutines** for asynchronous operations
- ngtcp2 C functions called via JNI
- TLS 1.3 via OpenSSL/BoringSSL

### Common Requirements

- **TLS 1.3** is required for QUIC
- **OpenSSL 3.0+** or **BoringSSL** for TLS backend
- **ngtcp2 1.21.0+** recommended
- **Single bidirectional stream** per MQTT connection

## References

- [NGTCP2 Integration Plan](./NGTCP2_INTEGRATION_PLAN.md) - Detailed implementation plan
- [iOS Build Instructions](./ios/NGTCP2_BUILD_INSTRUCTIONS.md) - iOS-specific build guide
- [Android Build Instructions](./android/NGTCP2_BUILD_INSTRUCTIONS.md) - Android-specific build guide
- [ngtcp2 Documentation](https://nghttp2.org/ngtcp2/)
- [ngtcp2 GitHub](https://github.com/ngtcp2/ngtcp2)

## Timeline

| Phase | Status | Estimated Time |
|-------|--------|----------------|
| Phase 1: iOS Structure | ✅ Complete | - |
| Phase 1: iOS Build & Integration | ⏳ Pending | 2-3 weeks |
| Phase 2: Android Structure | ✅ Complete | - |
| Phase 2: Android Build & Integration | ⏳ Pending | 2-3 weeks |
| Phase 3: Replace Stubs | ⏳ Pending | 1-2 weeks |
| Phase 4: Testing | ⏳ Pending | 1-2 weeks |
| Phase 5: Documentation | ⏳ Pending | 1 week |
| **Total** | **In Progress** | **7-11 weeks** |

## Notes

- The current implementation provides the **structure and foundation** for ngtcp2 integration
- **TODO comments** in the code indicate where ngtcp2 C API calls need to be implemented
- Build scripts are ready to use once ngtcp2 source is available
- The implementation follows the architecture outlined in `NGTCP2_INTEGRATION_PLAN.md`
