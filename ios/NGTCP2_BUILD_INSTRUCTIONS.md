# Building ngtcp2 for iOS

This document provides instructions for building ngtcp2 and OpenSSL for iOS to enable real QUIC transport in the MQTT client.

## Prerequisites

- **Xcode 14+** (for iOS 15+)
- **CMake 3.20+**
- **iOS SDK 15.0+**
- **Git** (for cloning repositories)

**Source layout:** set `PROJECT_DIR` to the `capacitor-mqtt-quic` repo root.
Build scripts then expect dependencies under:
- `$PROJECT_DIR/ref-code/ngtcp2`
- `$PROJECT_DIR/ref-code/nghttp3`
- `$PROJECT_DIR/ref-code/openssl` (or `$PROJECT_DIR/ref-code.openssl`)

```bash
export PROJECT_DIR="/Users/annadata/Project_A/annadata-production/ref-code/capacitor-mqtt-quic"
```

Override with `NGTCP2_SOURCE_DIR`, `NGHTTP3_SOURCE_DIR`, `OPENSSL_SOURCE_DIR`
if you store sources elsewhere.

**Version pinning:** Build scripts source `deps-versions.sh` in the plugin root and pin ngtcp2, nghttp3, and OpenSSL to fixed git commits for reproducible builds and server compatibility. Edit `deps-versions.sh` to change `NGTCP2_COMMIT`, `NGHTTP3_COMMIT`, or `OPENSSL_COMMIT`.

## Quick Start

### Option 1: Use Pre-built Libraries (Recommended for Development)

If you have access to pre-built ngtcp2, nghttp3, and OpenSSL libraries:

1. Place `libngtcp2.a` in `ios/libs/`
2. Place `libnghttp3.a` in `ios/libs/`
3. Place OpenSSL libraries (`libssl.a`, `libcrypto.a`) in `ios/libs/`
4. Place headers in `ios/include/ngtcp2/`, `ios/include/nghttp3/`, and `ios/include/openssl/`
5. Update `AnnadataCapacitorMqttQuic.podspec` to link against these libraries

### Option 2: Build from Source

#### Step 1: Build OpenSSL for iOS (QUIC TLS)

```bash
cd ios
./build-openssl.sh --arch arm64 --sdk iphoneos --quictls
```

This will:
- Clone QuicTLS (https://github.com/quictls/quictls) if not present (OpenSSL fork with QUIC API)
- Build static libraries for iOS
- Install to `ios/install/openssl-ios/`
- Sync `libssl.a`, `libcrypto.a` to `ios/libs/` and headers to `ios/include/openssl/`

**Note:** For simulator builds, use:
```bash
./build-openssl.sh --arch x86_64 --sdk iphonesimulator
```

#### Step 2: Build nghttp3 for iOS

```bash
cd ios
./build-nghttp3.sh \
  --arch arm64 \
  --sdk iphoneos
```

This will:
- Build nghttp3 static library
- Install to `ios/build/nghttp3-ios-arm64/install/`
- Sync `libnghttp3.a` to `ios/libs/` and headers to `ios/include/nghttp3/`

#### Step 3: Build ngtcp2 for iOS

```bash
cd ios
./build-ngtcp2.sh \
  --openssl-path ./install/openssl-ios \
  --arch arm64 \
  --sdk iphoneos \
  --quictls
```

This will:
- Build ngtcp2 static library
- Link against OpenSSL (quictls)
- Install to `ios/build/ios-arm64/install/`
- Sync `libngtcp2.a` and `libngtcp2_crypto_quictls.a` to `ios/libs/` and headers to `ios/include/ngtcp2/`

#### Step 4: Build for Multiple Architectures

For a universal library (arm64 + x86_64 for simulator):

```bash
# Build for device (arm64)
./build-openssl.sh --arch arm64 --sdk iphoneos --quictls
./build-nghttp3.sh --arch arm64 --sdk iphoneos
./build-ngtcp2.sh --openssl-path ./install/openssl-ios --arch arm64 --sdk iphoneos --quictls

# Build for simulator (x86_64)
./build-openssl.sh --arch x86_64 --sdk iphonesimulator --quictls
./build-nghttp3.sh --arch x86_64 --sdk iphonesimulator
./build-ngtcp2.sh --openssl-path ./install/openssl-ios --arch x86_64 --sdk iphonesimulator --quictls

# Create universal library
lipo -create \
  build/ios-arm64/install/lib/libngtcp2.a \
  build/ios-x86_64/install/lib/libngtcp2.a \
  -output libs/libngtcp2-universal.a

# Create universal nghttp3 library
lipo -create \
  build/nghttp3-ios-arm64/install/lib/libnghttp3.a \
  build/nghttp3-ios-x86_64/install/lib/libnghttp3.a \
  -output libs/libnghttp3-universal.a

# Create universal ngtcp2_crypto_quictls library
lipo -create \
  build/ios-arm64/install/lib/libngtcp2_crypto_quictls.a \
  build/ios-x86_64/install/lib/libngtcp2_crypto_quictls.a \
  -output libs/libngtcp2_crypto_quictls-universal.a
```

## Swift Package Manager (SPM) – create xcframework

If the app uses **Swift Package Manager** (Capacitor 8 SPM flow), the plugin’s `Package.swift` expects `Libs/MqttQuicLibs.xcframework`. After building OpenSSL, ngtcp2, and nghttp3 (Steps 1–3 above) so that `ios/libs/` contains the five `.a` files, run:

```bash
cd ios
./create-xcframework.sh
```

This merges `libs/*.a` into a single static library and creates `Libs/MqttQuicLibs.xcframework`. The app can then resolve the MqttQuicPlugin package and link the native plugin. Without this step, SPM will fail to resolve the plugin (binary target missing).

### Server returns -225 (NGTCP2_ERR_TRANSPORT_PARAM) and “Decoded client transport params: (NULL)”

That indicates a **client/server ngtcp2 version mismatch**. Rebuild the client’s ngtcp2 and xcframework using the **same** ngtcp2 version (same git tag/commit) as the server’s libngtcp2:

```bash
# From plugin root (ref-code/capacitor-mqtt-quic)
cd ios
# Use the same ngtcp2 version as the server (e.g. v1.2.0 or the server’s commit)
NGTCP2_SOURCE_DIR="${PWD}/../deps/ngtcp2"  # or set to your ngtcp2 clone
[ -d "$NGTCP2_SOURCE_DIR" ] && (cd "$NGTCP2_SOURCE_DIR" && git fetch && git checkout v1.2.0)  # replace with server’s version
./build-ngtcp2.sh --openssl-path /path/to/openssl-ios  # your usual args
./create-xcframework.sh
```

Then clean and rebuild the iOS app so it links the new xcframework. See the app’s `CONNECT_TROUBLESHOOTING.md` (section 5) for more detail.

---

## Integration into Xcode Project

### Option A: CocoaPods

Update `ios/AnnadataCapacitorMqttQuic.podspec`:

```ruby
Pod::Spec.new do |s|
  # ... existing configuration ...
  
  # ngtcp2 static library
  s.vendored_libraries = 'libs/libngtcp2.a', 'libs/libngtcp2_crypto_quictls.a', 'libs/libnghttp3.a', 'libs/libssl.a', 'libs/libcrypto.a'
  
  # Header search paths
  s.public_header_files = 'Sources/**/*.h'
  s.private_header_files = 'Sources/**/*.h'
  s.header_mappings_dir = 'Sources'
  
  # Include ngtcp2/nghttp3 headers
  s.xcconfig = {
    'HEADER_SEARCH_PATHS' => '$(PODS_ROOT)/MqttQuicPlugin/include/ngtcp2 $(PODS_ROOT)/MqttQuicPlugin/include/nghttp3 $(PODS_ROOT)/MqttQuicPlugin/include/openssl',
    'LIBRARY_SEARCH_PATHS' => '$(PODS_ROOT)/MqttQuicPlugin/libs',
    'OTHER_LDFLAGS' => '-lngtcp2 -lngtcp2_crypto_quictls -lnghttp3 -lssl -lcrypto'
  }
  
  # OpenSSL dependency (if using CocoaPods)
  s.dependency 'OpenSSL-Universal', '~> 3.0'
end
```

### Option B: Manual Integration

1. Add `libngtcp2.a` and `libnghttp3.a` to Xcode project
2. Add header search paths:
   - `$(SRCROOT)/../ios/include/ngtcp2`
   - `$(SRCROOT)/../ios/include/nghttp3`
   - `$(SRCROOT)/../ios/include/openssl`
3. Link against:
   - `libngtcp2.a`
   - `libnghttp3.a`
   - `libssl.a` (OpenSSL)
   - `libcrypto.a` (OpenSSL)

## TLS Certificate Verification (QUIC)

QUIC requires TLS 1.3 and certificate verification is **enabled by default**.
You can bundle a CA PEM and it will be loaded automatically:

- `ios/Sources/MqttQuicPlugin/Resources/mqttquic_ca.pem`

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
- iOS: `ios/Sources/MqttQuicPlugin/Resources/mqttquic_ca.pem` (use `ca.pem`)

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

If you prefer to use pre-built libraries:

### OpenSSL

Download from:
- https://github.com/x2on/OpenSSL-for-iPhone
- https://github.com/krzyzanowskim/OpenSSL

### ngtcp2

Currently, there are no widely available pre-built ngtcp2 libraries for iOS. You'll need to build from source.

### nghttp3

Currently, there are no widely available pre-built nghttp3 libraries for iOS. You'll need to build from source. Make sure you clone with submodules:

```bash
git clone --recurse-submodules https://github.com/ngtcp2/nghttp3.git
```

## Troubleshooting

### CMake Not Found

```bash
# Install via Homebrew
brew install cmake
```

### OpenSSL Build Fails

- Ensure you're using OpenSSL 3.0+ (required for TLS 1.3)
- Check that Xcode command line tools are installed: `xcode-select --install`
- Verify SDK path: `xcrun --sdk iphoneos --show-sdk-path`

### ngtcp2 Build Fails

- Verify OpenSSL is built and path is correct
- Check CMake version: `cmake --version` (must be 3.20+)
- Ensure iOS deployment target matches (15.0+)

### Link Errors

- Verify all libraries are built for the same architecture
- Check that header search paths are correct
- Ensure OpenSSL and ngtcp2 are linked in the correct order

### Enabling wolfSSL debug (ERR_CRYPTO / TLS handshake)

To see why TLS verification fails (e.g. ERR_CRYPTO from ngtcp2/wolfSSL):

1. **Set the env var** before the QUIC connection runs:
   - In the host app (e.g. Xcode scheme or code): set `MQTT_QUIC_WOLFSSL_DEBUG=1`.
   - The plugin’s native code (`NGTCP2Bridge.mm`) checks this and calls `wolfSSL_Debugging_ON()` when the SSL context is created.

2. **Rebuild** the plugin (and the app that uses it), then connect. wolfSSL will print debug lines to stderr (Xcode console or device log) describing the handshake and any verification failure.

3. **Note:** Debug output only appears if wolfSSL was built with `DEBUG_WOLFSSL` (or equivalent). If you see no extra output, the wolfSSL library may be a release build; rebuild wolfSSL with debug enabled if you need the logs.

## Next Steps

After building ngtcp2:

1. Update `NGTCP2Client.swift` to implement the TODO sections
2. Replace `QuicClientStub` with `NGTCP2Client` in `MQTTClient.swift`
3. Test connection to MQTT server over QUIC

See [NGTCP2_INTEGRATION_PLAN.md](../docs/NGTCP2_INTEGRATION_PLAN.md) for detailed implementation guide.
