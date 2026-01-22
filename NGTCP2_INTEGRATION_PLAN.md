# ngtcp2 Integration Plan for Capacitor MQTT Client

## Overview

This document provides a detailed plan for integrating **ngtcp2** into the Capacitor MQTT-over-QUIC client plugin, replacing the current stub implementations with real QUIC transport.

**Current Status:**
- ✅ MQTT protocol layer (3.1.1 + 5.0) - Complete
- ✅ Transport abstraction (StreamReader/StreamWriter) - Complete
- ✅ MQTT client API - Complete
- ✅ Capacitor plugin bridge - Complete
- ⏳ **QUIC transport (ngtcp2)** - **PENDING** (currently using stubs)

**Reference:**
- Server implementation: `MQTTD/mqttd/transport_quic_ngtcp2.py`
- ngtcp2 source: `production/ngtcp2/`
- Client stubs: `ios/.../QuicClientStub.swift`, `android/.../QuicClientStub.kt`

---

## Phase 1: Build ngtcp2 for iOS (2-3 weeks)

### 1.1 Prerequisites

**Required:**
- Xcode 14+ (for iOS 15+)
- CMake 3.20+
- iOS SDK 15.0+
- OpenSSL or BoringSSL for TLS 1.3

**TLS Backend Options:**
- **OpenSSL 3.0+** (recommended - widely available)
- **BoringSSL** (Google's fork, used by Chromium)
- **wolfSSL 5.5+** (lightweight alternative)

### 1.2 Build ngtcp2 as Static Library for iOS

**Option A: Using CMake with iOS Toolchain (Recommended)**

```bash
cd /home/annadata/api/production/ngtcp2

# Create iOS build directory
mkdir -p build/ios
cd build/ios

# Download iOS CMake toolchain (if not available)
# https://github.com/leetal/ios-cmake

# Configure for iOS (arm64 - iPhone/iPad)
cmake ../.. \
  -DCMAKE_TOOLCHAIN_FILE=../../ios.toolchain.cmake \
  -DPLATFORM=OS64 \
  -DENABLE_LIB_ONLY=ON \
  -DENABLE_OPENSSL=ON \
  -DOPENSSL_ROOT_DIR=/path/to/openssl/ios \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=./install

# Build
cmake --build . --config Release

# Output: libngtcp2.a (static library)
```

**Option B: Using Autotools with Cross-Compilation**

```bash
cd /home/annadata/api/production/ngtcp2

# Set iOS SDK path
export IOS_SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
export CC=$(xcrun --sdk iphoneos --find clang)
export CXX=$(xcrun --sdk iphoneos --find clang++)

# Configure for iOS
./configure \
  --host=arm-apple-darwin \
  --prefix=/tmp/ngtcp2-ios \
  --enable-lib-only \
  --with-openssl=/path/to/openssl/ios \
  CC="$CC -arch arm64 -isysroot $IOS_SDK_PATH" \
  CXX="$CXX -arch arm64 -isysroot $IOS_SDK_PATH"

make -j$(sysctl -n hw.ncpu)
make install
```

### 1.3 Build OpenSSL for iOS

**Using OpenSSL:**

```bash
# Clone OpenSSL
git clone https://github.com/openssl/openssl.git
cd openssl

# Configure for iOS
./Configure ios64-cross \
  --prefix=/tmp/openssl-ios \
  no-shared \
  no-tests

make -j$(sysctl -n hw.ncpu)
make install
```

**Or use pre-built OpenSSL:**
- https://github.com/x2on/OpenSSL-for-iPhone
- https://github.com/krzyzanowskim/OpenSSL

### 1.4 Integrate into Xcode Project

**Option A: CocoaPods**

Create `ios/Podspec` or add to existing podspec:

```ruby
Pod::Spec.new do |s|
  s.name = 'ngtcp2'
  s.version = '1.21.0'
  s.source = { :path => '../../ngtcp2' }
  s.source_files = 'lib/**/*.{c,h}'
  s.public_header_files = 'lib/includes/ngtcp2/ngtcp2.h'
  s.vendored_libraries = 'build/ios/libngtcp2.a'
  s.dependency 'OpenSSL-Universal'
end
```

**Option B: Swift Package Manager (SPM)**

Create `Package.swift`:

```swift
// Package.swift
let package = Package(
  name: "ngtcp2",
  products: [
    .library(name: "ngtcp2", targets: ["ngtcp2"])
  ],
  targets: [
    .target(
      name: "ngtcp2",
      path: "lib",
      publicHeadersPath: "includes"
    )
  ]
)
```

**Option C: Manual Integration**

1. Add `libngtcp2.a` to Xcode project
2. Add header search paths: `$(SRCROOT)/../ngtcp2/lib/includes`
3. Link against `libngtcp2.a` and OpenSSL

### 1.5 Create Swift Wrapper

File: `ios/Sources/MqttQuicPlugin/QUIC/NGTCP2Client.swift`

```swift
import Foundation
import Network  // For NWConnection (UDP)

public final class NGTCP2Client: QuicClientProtocol {
    // ngtcp2 connection handle
    private var conn: OpaquePointer?
    
    // UDP connection
    private var udpConnection: NWConnection?
    
    // TLS context
    private var tlsContext: OpaquePointer?
    
    public func connect(host: String, port: UInt16) async throws {
        // 1. Create UDP connection (NWConnection)
        // 2. Initialize ngtcp2 client connection
        // 3. Start TLS 1.3 handshake
        // 4. Complete QUIC handshake
    }
    
    public func openStream() async throws -> QuicStreamProtocol {
        // Create QUIC stream using ngtcp2
    }
    
    public func close() async throws {
        // Close ngtcp2 connection
        // Close UDP connection
    }
}
```

**Key Implementation Points:**
- Use `NWConnection` (Network framework) for UDP
- Call ngtcp2 C functions via Swift C interop
- Handle TLS 1.3 handshake via OpenSSL/BoringSSL
- Implement packet send/receive callbacks

---

## Phase 2: Build ngtcp2 for Android (2-3 weeks)

### 2.1 Prerequisites

**Required:**
- Android NDK r25+ (for CMake support)
- CMake 3.20+
- Android SDK 21+ (API level 21 = Android 5.0)
- OpenSSL or BoringSSL for TLS 1.3

### 2.2 Build ngtcp2 with Android NDK

**Create `android/ngtcp2/CMakeLists.txt`:**

```cmake
cmake_minimum_required(VERSION 3.20)
project(ngtcp2)

# Set Android-specific flags
set(CMAKE_SYSTEM_NAME Android)
set(CMAKE_ANDROID_ARCH_ABI arm64-v8a)  # or armeabi-v7a, x86_64
set(CMAKE_ANDROID_NDK ${ANDROID_NDK})

# Find OpenSSL (built for Android)
find_package(OpenSSL REQUIRED)

# Add ngtcp2 source files
add_subdirectory(../../ngtcp2 libngtcp2)

# Create shared library
add_library(ngtcp2_client SHARED
    src/main/cpp/ngtcp2_jni.cpp
)

target_link_libraries(ngtcp2_client
    ngtcp2
    OpenSSL::SSL
    OpenSSL::Crypto
    log
)
```

**Build script `android/ngtcp2/build.sh`:**

```bash
#!/bin/bash
set -e

ANDROID_NDK=/path/to/android-ndk-r25c
ANDROID_ABI=arm64-v8a
ANDROID_PLATFORM=android-21

mkdir -p build/android
cd build/android

cmake ../.. \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=$ANDROID_ABI \
  -DANDROID_PLATFORM=$ANDROID_PLATFORM \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_LIB_ONLY=ON \
  -DENABLE_OPENSSL=ON

cmake --build . --config Release

# Output: libngtcp2_client.so
```

### 2.3 Build OpenSSL for Android

**Using OpenSSL build script:**

```bash
# Clone OpenSSL
git clone https://github.com/openssl/openssl.git
cd openssl

# Build for Android
./Configure android-arm64 \
  --prefix=/tmp/openssl-android \
  no-shared \
  no-tests

make -j$(nproc)
make install
```

**Or use pre-built:**
- https://github.com/leenjewel/openssl_for_ios_and_android

### 2.4 Create JNI Wrapper

**File: `android/src/main/cpp/ngtcp2_jni.cpp`**

```cpp
#include <jni.h>
#include <ngtcp2/ngtcp2.h>
#include <openssl/ssl.h>

extern "C" {

JNIEXPORT jlong JNICALL
Java_ai_annadata_mqttquic_quic_NGTCP2Client_nativeCreateConnection(
    JNIEnv *env, jobject thiz, jstring host, jint port) {
    // Create ngtcp2 client connection
    // Return connection handle as jlong
}

JNIEXPORT jint JNICALL
Java_ai_annadata_mqttquic_quic_NGTCP2Client_nativeConnect(
    JNIEnv *env, jobject thiz, jlong connHandle) {
    // Start QUIC connection
}

JNIEXPORT jlong JNICALL
Java_ai_annadata_mqttquic_quic_NGTCP2Client_nativeOpenStream(
    JNIEnv *env, jobject thiz, jlong connHandle) {
    // Open QUIC stream
    // Return stream ID as jlong
}

JNIEXPORT jint JNICALL
Java_ai_annadata_mqttquic_quic_NGTCP2Client_nativeWriteStream(
    JNIEnv *env, jobject thiz, jlong connHandle, jlong streamId, jbyteArray data) {
    // Write data to stream
}

JNIEXPORT jbyteArray JNICALL
Java_ai_annadata_mqttquic_quic_NGTCP2Client_nativeReadStream(
    JNIEnv *env, jobject thiz, jlong connHandle, jlong streamId) {
    // Read data from stream
}

JNIEXPORT void JNICALL
Java_ai_annadata_mqttquic_quic_NGTCP2Client_nativeClose(
    JNIEnv *env, jobject thiz, jlong connHandle) {
    // Close connection
}

}
```

### 2.5 Create Kotlin Wrapper

**File: `android/src/main/kotlin/ai/annadata/mqttquic/quic/NGTCP2Client.kt`**

```kotlin
package ai.annadata.mqttquic.quic

import java.net.DatagramSocket
import java.net.InetSocketAddress

class NGTCP2Client : QuicClient {
    private external fun nativeCreateConnection(host: String, port: Int): Long
    private external fun nativeConnect(connHandle: Long): Int
    private external fun nativeOpenStream(connHandle: Long): Long
    private external fun nativeWriteStream(connHandle: Long, streamId: Long, data: ByteArray): Int
    private external fun nativeReadStream(connHandle: Long, streamId: Long): ByteArray?
    private external fun nativeClose(connHandle: Long)
    
    private var connHandle: Long = 0
    private val udpSocket = DatagramSocket()
    
    init {
        System.loadLibrary("ngtcp2_client")
    }
    
    override suspend fun connect(host: String, port: Int) {
        connHandle = nativeCreateConnection(host, port)
        val result = nativeConnect(connHandle)
        if (result != 0) {
            throw Exception("QUIC connection failed: $result")
        }
    }
    
    override suspend fun openStream(): QuicStream {
        val streamId = nativeOpenStream(connHandle)
        return NGTCP2Stream(connHandle, streamId)
    }
    
    override suspend fun close() {
        nativeClose(connHandle)
        udpSocket.close()
    }
}
```

---

## Phase 3: Replace Stubs with Real Implementation (1-2 weeks)

### 3.1 iOS Implementation

**Update `MQTTClient.swift`:**

```swift
// Replace QuicClientStub with NGTCP2Client
let quic = NGTCP2Client()  // Instead of QuicClientStub
try await quic.connect(host: host, port: port)
```

**Key Changes:**
1. Remove `QuicClientStub.swift` (or keep for testing)
2. Use `NGTCP2Client` in `MQTTClient.connect()`
3. Handle real UDP/TLS errors
4. Implement proper connection state management

### 3.2 Android Implementation

**Update `MQTTClient.kt`:**

```kotlin
// Replace QuicClientStub with NGTCP2Client
val quic = NGTCP2Client()  // Instead of QuicClientStub
quic.connect(host, port)
```

**Key Changes:**
1. Remove `QuicClientStub.kt` (or keep for testing)
2. Use `NGTCP2Client` in `MQTTClient.connect()`
3. Handle real UDP/TLS errors
4. Implement proper connection state management

---

## Phase 4: Testing (1-2 weeks)

### 4.1 Unit Tests

**iOS:**
- Test ngtcp2 connection creation
- Test stream open/read/write
- Test TLS handshake
- Test error handling

**Android:**
- Test JNI wrapper functions
- Test connection lifecycle
- Test stream operations
- Test error handling

### 4.2 Integration Tests

**Test against MQTTD server:**

```typescript
// Test MQTT over QUIC connection
await MqttQuic.connect({
  host: 'mqtt.annadata.cloud',
  port: 1884,
  clientId: 'test_client',
  protocolVersion: '5.0'
});

// Test publish
await MqttQuic.publish({
  topic: 'test/topic',
  payload: 'Hello QUIC!'
});

// Test subscribe
await MqttQuic.subscribe({
  topic: 'test/+'
});
```

### 4.3 Performance Testing

- Connection establishment time
- Message latency (publish → receive)
- Throughput (messages/second)
- Memory usage
- Battery impact

---

## Phase 5: Documentation & Deployment (1 week)

### 5.1 Documentation

- Update `README.md` with build instructions
- Document ngtcp2 integration
- Add troubleshooting guide
- Document TLS certificate requirements

### 5.2 CI/CD Integration

- Add iOS build to CI (Xcode Cloud or GitHub Actions)
- Add Android build to CI
- Automated testing

---

## Timeline Summary

| Phase | Duration | Status |
|-------|----------|--------|
| Phase 1: Build ngtcp2 for iOS | 2-3 weeks | ⏳ Pending |
| Phase 2: Build ngtcp2 for Android | 2-3 weeks | ⏳ Pending |
| Phase 3: Replace stubs | 1-2 weeks | ⏳ Pending |
| Phase 4: Testing | 1-2 weeks | ⏳ Pending |
| Phase 5: Documentation | 1 week | ⏳ Pending |
| **Total** | **7-11 weeks** | |

---

## Resources

### ngtcp2 Documentation
- Official: https://nghttp2.org/ngtcp2/
- GitHub: https://github.com/ngtcp2/ngtcp2
- Examples: `production/ngtcp2/examples/`

### Reference Implementations
- Server: `MQTTD/mqttd/transport_quic_ngtcp2.py`
- curl: `curl/lib/vquic/curl_ngtcp2.c`
- ngtcp2 examples: `production/ngtcp2/examples/client.cc`

### Build Tools
- iOS CMake toolchain: https://github.com/leetal/ios-cmake
- Android NDK: https://developer.android.com/ndk
- OpenSSL for mobile: https://github.com/x2on/OpenSSL-for-iPhone

---

## Next Steps

1. **Start with iOS** (simpler build process)
   - Set up CMake build for iOS
   - Build OpenSSL for iOS
   - Create Swift wrapper

2. **Then Android** (more complex due to JNI)
   - Set up NDK build
   - Build OpenSSL for Android
   - Create JNI wrapper

3. **Test incrementally**
   - Test connection establishment first
   - Then stream operations
   - Finally full MQTT flow

4. **Iterate and refine**
   - Fix issues as they arise
   - Optimize performance
   - Improve error handling

---

## Notes

- **TLS Backend**: OpenSSL is recommended for both platforms (widely available, well-documented)
- **Static vs Dynamic**: Static libraries (`.a`/`.lib`) are preferred for mobile apps (no runtime dependencies)
- **Architecture Support**: Start with arm64 (iPhone/iPad, modern Android), add x86_64 later if needed for simulators
- **Version Pinning**: Pin ngtcp2 version (e.g., 1.21.0) for reproducible builds
