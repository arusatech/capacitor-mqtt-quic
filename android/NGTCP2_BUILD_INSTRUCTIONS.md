# Building ngtcp2 for Android

This document provides instructions for building ngtcp2 and OpenSSL for Android to enable real QUIC transport in the MQTT client.

## Prerequisites

- **Android NDK r25+**
- **CMake 3.20+**
- **Android SDK 21+** (API level 21 = Android 5.0)
- **Git** (for cloning repositories)

## Quick Start

### Option 1: Use Pre-built Libraries (Recommended for Development)

If you have access to pre-built ngtcp2 and OpenSSL libraries:

1. Place `libngtcp2_client.so` in `android/src/main/jniLibs/<abi>/`
2. Place OpenSSL libraries (`libssl.a`, `libcrypto.a`) in `android/libs/<abi>/`
3. Update `build.gradle` to link against these libraries

### Option 2: Build from Source

#### Step 1: Build OpenSSL for Android

```bash
cd android
./build-openssl.sh \
  --ndk-path ~/Android/Sdk/ndk/25.2.9519653 \
  --abi arm64-v8a \
  --platform android-21
```

This will:
- Clone OpenSSL (if not present)
- Build static libraries for Android
- Install to `android/install/openssl-android/`

**Note:** For different ABIs, repeat the build:
```bash
# arm64-v8a (64-bit ARM)
./build-openssl.sh --ndk-path ~/Android/Sdk/ndk/25.2.9519653 --abi arm64-v8a

# armeabi-v7a (32-bit ARM)
./build-openssl.sh --ndk-path ~/Android/Sdk/ndk/25.2.9519653 --abi armeabi-v7a

# x86_64 (64-bit x86)
./build-openssl.sh --ndk-path ~/Android/Sdk/ndk/25.2.9519653 --abi x86_64
```

#### Step 2: Build ngtcp2 for Android

```bash
cd android
./build-ngtcp2.sh \
  --ndk-path ~/Android/Sdk/ndk/25.2.9519653 \
  --abi arm64-v8a \
  --platform android-21 \
  --openssl-path ./install/openssl-android
```

This will:
- Build ngtcp2 static library
- Link against OpenSSL
- Install to `android/build/android-arm64-v8a/install/`

#### Step 3: Build JNI Library

The JNI wrapper (`ngtcp2_jni.cpp`) is built as part of the Android project using CMake.

Update `android/build.gradle`:

```gradle
android {
    // ...
    externalNativeBuild {
        cmake {
            path "src/main/cpp/CMakeLists.txt"
            version "3.22.1"
        }
    }
    
    ndk {
        abiFilters 'arm64-v8a', 'armeabi-v7a', 'x86_64'
    }
}
```

## Integration into Android Project

### Update build.gradle

Add CMake configuration:

```gradle
android {
    compileSdkVersion 34
    
    defaultConfig {
        // ...
        externalNativeBuild {
            cmake {
                arguments "-DANDROID_STL=c++_shared"
                cppFlags "-std=c++17"
            }
        }
        ndk {
            abiFilters 'arm64-v8a', 'armeabi-v7a', 'x86_64'
        }
    }
    
    externalNativeBuild {
        cmake {
            path "src/main/cpp/CMakeLists.txt"
            version "3.22.1"
        }
    }
}
```

### Update CMakeLists.txt

Ensure `CMakeLists.txt` points to correct ngtcp2 and OpenSSL paths:

```cmake
# Set paths
set(NGTCP2_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../ngtcp2")
set(OPENSSL_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../install/openssl-android")
```

## Using Pre-built Libraries

### OpenSSL

Download from:
- https://github.com/leenjewel/openssl_for_ios_and_android

### ngtcp2

Currently, there are no widely available pre-built ngtcp2 libraries for Android. You'll need to build from source.

## Troubleshooting

### NDK Not Found

```bash
# Install via Android Studio SDK Manager
# Or download from: https://developer.android.com/ndk/downloads
```

### CMake Not Found

```bash
# Install via Android Studio SDK Manager
# Or download from: https://cmake.org/download/
```

### OpenSSL Build Fails

- Ensure you're using OpenSSL 3.0+ (required for TLS 1.3)
- Check that NDK path is correct
- Verify ABI is supported (arm64-v8a, armeabi-v7a, x86_64, x86)

### ngtcp2 Build Fails

- Verify OpenSSL is built and path is correct
- Check CMake version: `cmake --version` (must be 3.20+)
- Ensure Android platform matches (android-21+)

### Link Errors

- Verify all libraries are built for the same ABI
- Check that CMakeLists.txt paths are correct
- Ensure OpenSSL and ngtcp2 are linked in the correct order

### JNI Errors

- Verify native method names match exactly (package + class + method)
- Check that `System.loadLibrary("ngtcp2_client")` is called
- Ensure library is in correct ABI folder: `src/main/jniLibs/<abi>/`

## Next Steps

After building ngtcp2:

1. Update `ngtcp2_jni.cpp` to implement the TODO sections
2. Replace `QuicClientStub` with `NGTCP2Client` in `MQTTClient.kt`
3. Test connection to MQTT server over QUIC

See `NGTCP2_INTEGRATION_PLAN.md` for detailed implementation guide.
