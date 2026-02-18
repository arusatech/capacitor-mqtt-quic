# Building ngtcp2 for Android

This document provides instructions for building ngtcp2 and WolfSSL (wolfssl-android) for Android to enable real QUIC transport in the MQTT client. The plugin uses WolfSSL by default; optional QuicTLS/OpenSSL build paths are also documented.

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
- `$PROJECT_DIR/ref-code/wolfssl` (default) or `$PROJECT_DIR/ref-code/openssl` (optional QuicTLS)

```bash
export PROJECT_DIR="/path/to/capacitor-mqtt-quic"
```

Override with `NGTCP2_SOURCE_DIR`, `NGHTTP3_SOURCE_DIR`, `WOLFSSL_SOURCE_DIR` (or `OPENSSL_SOURCE_DIR` for QuicTLS) if you store sources elsewhere.

## Quick Start

### Option 1: Use Pre-built Libraries (Recommended for Development)

If you have access to pre-built ngtcp2, nghttp3, and WolfSSL libraries:

1. Place ngtcp2/nghttp3 static libs in `android/install/ngtcp2-android/<abi>/` and `android/install/nghttp3-android/<abi>/`
2. Place WolfSSL (`libwolfssl.a`) in `android/install/wolfssl-android/<abi>/`
3. Update `CMakeLists.txt` to point at `android/install/` (plugin expects wolfssl-android by default)

### Option 2: Build from Source (WolfSSL – default)

From the **plugin repo root** (not `android/`), run:

```bash
./build-native.sh --android-only --abi arm64-v8a
./build-native.sh --android-only --abi armeabi-v7a
./build-native.sh --android-only --abi x86_64
```

This builds WolfSSL → nghttp3 → ngtcp2 and installs to:
- `android/install/wolfssl-android/<abi>/`
- `android/install/nghttp3-android/<abi>/`
- `android/install/ngtcp2-android/<abi>/`

**Or** from `android/` use the individual scripts:

```bash
cd android
./build-wolfssl.sh --ndk-path ~/Android/Sdk/ndk/25.2.9519653 --platform android-21 --abi arm64-v8a
./build-nghttp3.sh --ndk-path ~/Android/Sdk/ndk/25.2.9519653 --platform android-21 --abi arm64-v8a
./build-ngtcp2.sh --abi arm64-v8a --platform android-21
```

Repeat for `armeabi-v7a` and `x86_64` as needed.

### Option 3: Build from Source (QuicTLS/OpenSSL – optional)

If you need OpenSSL/QuicTLS instead of WolfSSL:

```bash
cd android
./build-openssl.sh \
  --ndk-path ~/Library/Android/sdk/ndk/<ndk-version> \
  --abi arm64-v8a \
  --platform android-21 \
  --quictls
```

This will:
- Clone QuicTLS (https://github.com/quictls/quictls) if not present (OpenSSL fork with QUIC API)
- Install to `android/install/openssl-android/<abi>/`

**Note:** The plugin’s CMake is configured for **WolfSSL** by default. Use Option 2 for the standard plugin build.

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

#### Step 3: Build ngtcp2 for Android (WolfSSL – default)

```bash
cd android
./build-ngtcp2.sh \
  --ndk-path ~/Library/Android/sdk/ndk/<ndk-version> \
  --abi arm64-v8a \
  --platform android-21 \
  --wolfssl-path ./install/wolfssl-android/arm64-v8a
```

This will:
- Build ngtcp2 static library with WolfSSL crypto
- Install to `android/install/ngtcp2-android/<abi>/`

Example: `./build-ngtcp2.sh --abi arm64-v8a --platform android-21 --wolfssl-path ./install/wolfssl-android/arm64-v8a`

If using QuicTLS/OpenSSL instead: `./build-ngtcp2.sh --abi arm64-v8a --platform android-21 --openssl-path ./install/openssl-android --quictls`

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

Ensure `CMakeLists.txt` points to correct ngtcp2 and WolfSSL paths (plugin default):

```cmake
# Set paths (WolfSSL default)
set(NGTCP2_INSTALL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../install/ngtcp2-android/${ANDROID_ABI}")
set(NGHTTP3_INSTALL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../install/nghttp3-android/${ANDROID_ABI}")
set(WOLFSSL_INSTALL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../install/wolfssl-android/${ANDROID_ABI}")
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

### WolfSSL (default)

Build using `./build-wolfssl.sh` or `./build-native.sh --android-only` (see Option 2 above). Pre-built WolfSSL for Android can also be obtained from the wolfSSL project.

### OpenSSL / QuicTLS (optional)

If building with QuicTLS instead of WolfSSL, download from:
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

### WolfSSL Build Fails

- Ensure WolfSSL is built for the correct ABI (arm64-v8a, armeabi-v7a, x86_64)
- Check that NDK path is correct
- Run `./build-wolfssl.sh` from `android/` or `./build-native.sh --android-only` from plugin root

### OpenSSL/QuicTLS Build Fails (optional path)

- Ensure you're using OpenSSL 3.0+ (required for TLS 1.3)
- Check that NDK path is correct
- Verify ABI is supported (arm64-v8a, armeabi-v7a, x86_64, x86)

### ngtcp2 Build Fails

- Verify WolfSSL (or OpenSSL) is built and path is correct (`--wolfssl-path` or `--openssl-path`)
- Check CMake version: `cmake --version` (must be 3.20+)
- Ensure Android platform matches (android-21+)

### Link Errors

- Verify all libraries are built for the same ABI
- Check that CMakeLists.txt paths are correct (wolfssl-android for default)
- Ensure WolfSSL/ngtcp2 and nghttp3 are linked in the correct order

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
