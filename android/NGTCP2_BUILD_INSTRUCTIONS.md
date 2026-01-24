# Building ngtcp2 for Android

This document provides instructions for building ngtcp2 and OpenSSL for Android to enable real QUIC transport in the MQTT client.

## Prerequisites

- **Android NDK r25+**
- **CMake 3.20+**
- **Android SDK 21+** (API level 21 = Android 5.0)
- **Git** (for cloning repositories)

**NDK path tip:** the build scripts auto-detect NDK installs in
`~/Library/Android/sdk/ndk` (macOS) or `~/Android/Sdk/ndk` (Linux). You can
omit `--ndk-path` if your NDK is installed in one of those locations.

**Source layout:** set `PROJECT_DIR` to the `capacitor-mqtt-quic` repo root.
Build scripts then expect dependencies under:
- `$PROJECT_DIR/ref-code/ngtcp2`
- `$PROJECT_DIR/ref-code/nghttp3`
- `$PROJECT_DIR/ref-code/openssl`

```bash
export PROJECT_DIR="/Users/annadata/Project_A/annadata-production/ref-code/capacitor-mqtt-quic"
```

Override with `NGTCP2_SOURCE_DIR`, `NGHTTP3_SOURCE_DIR`, `OPENSSL_SOURCE_DIR`
if you store sources elsewhere.

## Quick Start

### Option 1: Use Pre-built Libraries (Recommended for Development)

If you have access to pre-built ngtcp2, nghttp3, and OpenSSL libraries:

1. Place `libngtcp2_client.so` in `android/src/main/jniLibs/<abi>/`
2. Place `libnghttp3.a` in `android/libs/<abi>/`
3. Place OpenSSL libraries (`libssl.a`, `libcrypto.a`) in `android/libs/<abi>/`
4. Update `build.gradle` and `CMakeLists.txt` to link against these libraries

### Option 2: Build from Source

#### Step 1: Build OpenSSL for Android (QUIC TLS)

```bash
cd android
./build-openssl.sh \
  --ndk-path ~/Library/Android/sdk/ndk/<ndk-version> \
  --abi arm64-v8a \
  --platform android-21 \
  --quictls
```

This will:
- Clone quictls (OpenSSL fork with QUIC API) if not present
- Build static libraries for Android
- Install to `android/install/openssl-android/<abi>/`

**Note:** For different ABIs, repeat the build:
```bash
# arm64-v8a (64-bit ARM)
./build-openssl.sh --ndk-path ~/Android/Sdk/ndk/25.2.9519653 --platform android-21 --abi arm64-v8a --quictls
# ./build-openssl.sh --ndk-path "/Users/annadata/Library/Android/sdk/ndk/29.0.13113456" --abi arm64-v8a --platform android-21 --quictls

# armeabi-v7a (32-bit ARM)
./build-openssl.sh --ndk-path ~/Android/Sdk/ndk/25.2.9519653 --platform android-21 --abi armeabi-v7a --quictls
# ./build-openssl.sh --ndk-path "/Users/annadata/Library/Android/sdk/ndk/29.0.13113456" --abi armeabi-v7a --platform android-21 --quictls

# x86_64 (64-bit x86)
./build-openssl.sh --ndk-path ~/Android/Sdk/ndk/25.2.9519653 --platform android-21 --abi x86_64 --quictls
# ./build-openssl.sh --ndk-path "/Users/annadata/Library/Android/sdk/ndk/29.0.13113456" --abi x86_64 --platform android-21 --quictls
```

#### Step 2: Build nghttp3 for Android

```bash
cd android
./build-nghttp3.sh \
  --ndk-path ~/Library/Android/sdk/ndk/<ndk-version> \
  --abi arm64-v8a \
  --platform android-21
```

This will:
- Build nghttp3 static library
- Install to `android/install/nghttp3-android/<abi>/`

- ./build-nghttp3.sh --abi arm64-v8a --platform android-21

#### Step 3: Build ngtcp2 for Android

```bash
cd android
./build-ngtcp2.sh \
  --ndk-path ~/Library/Android/sdk/ndk/<ndk-version> \
  --abi arm64-v8a \
  --platform android-21 \
  --openssl-path ./install/openssl-android/arm64-v8a \
  --quictls
```

This will:
- Build ngtcp2 static library
- Link against OpenSSL
- Install to `android/install/ngtcp2-android/<abi>/`
./build-ngtcp2.sh --abi arm64-v8a --platform android-21 --openssl-path ./install/openssl-android --quictls

#### Step 4: Build JNI Library

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
set(NGHTTP3_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../nghttp3")
set(OPENSSL_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../install/openssl-android")
```

## TLS Certificate Verification (QUIC)

QUIC requires TLS 1.3 and certificate verification is **enabled by default**.
You can bundle a CA PEM and it will be loaded automatically:

- `android/src/main/assets/mqttquic_ca.pem`

You can also override per call:

```ts
await MqttQuic.connect({
  host: 'mqtt.example.com',
  port: 1884,
  clientId: 'my-client-id',
  caFile: '/path/to/ca-bundle.pem',
  // or caPath: '/path/to/ca-directory'
});
```

### How to generate certificates

**Option A: Public CA (Let’s Encrypt)**  
You do not bundle `mqttquic_ca.pem` (the OS already trusts public CAs).

```bash
sudo apt-get update
sudo apt-get install -y certbot
sudo certbot certonly --standalone -d mqtt.example.com
```

Use on server:
- Cert: `/etc/letsencrypt/live/mqtt.example.com/fullchain.pem`
- Key: `/etc/letsencrypt/live/mqtt.example.com/privkey.pem`

**Option B: Private CA (dev/internal)**  
Generate your own CA, sign the server cert, and bundle the CA PEM.

```bash
mkdir -p certs && cd certs

# 1) Create CA (one-time)
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -out ca.pem \
  -subj "/C=US/ST=CA/L=SF/O=Annadata/OU=MQTT/CN=Annadata-Root-CA"

# 2) Create server key + CSR
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr \
  -subj "/C=US/ST=CA/L=SF/O=Annadata/OU=MQTT/CN=mqtt.example.com"

# 3) Add SANs (edit DNS/IP)
cat > server_ext.cnf <<EOF
subjectAltName = DNS:mqtt.example.com,IP:YOUR.SERVER.IP
extendedKeyUsage = serverAuth
EOF

# 4) Sign server cert
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
  -out server.pem -days 365 -sha256 -extfile server_ext.cnf
```

Bundle the CA cert (never ship `ca.key`):
- Android: `android/src/main/assets/mqttquic_ca.pem` (use `ca.pem`)

## Test Harness (QUIC Smoke Test)

This runs: connect → subscribe → publish → disconnect.

```ts
await MqttQuic.testHarness({
  host: 'mqtt.example.com',
  port: 1884,
  clientId: 'mqttquic_test_client',
  topic: 'test/topic',
  payload: 'Hello QUIC!',
  // optional CA override
  caFile: '/path/to/ca-bundle.pem'
});
```

## Using Pre-built Libraries

### OpenSSL

Download from:
- https://github.com/leenjewel/openssl_for_ios_and_android

### ngtcp2

Currently, there are no widely available pre-built ngtcp2 libraries for Android. You'll need to build from source.

### nghttp3

Currently, there are no widely available pre-built nghttp3 libraries for Android. You'll need to build from source. Make sure you clone with submodules:

```bash
git clone --recurse-submodules https://github.com/ngtcp2/nghttp3.git
```

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

After building ngtcp2/nghttp3:

1. Update `ngtcp2_jni.cpp` to implement the TODO sections
2. Replace `QuicClientStub` with `NGTCP2Client` in `MQTTClient.kt`
3. Test connection to MQTT server over QUIC

See `NGTCP2_INTEGRATION_PLAN.md` for detailed implementation guide.
