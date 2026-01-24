# Building ngtcp2 for iOS

This document provides instructions for building ngtcp2 and OpenSSL for iOS to enable real QUIC transport in the MQTT client.

## Prerequisites

- **Xcode 14+** (for iOS 15+)
- **CMake 3.20+**
- **iOS SDK 15.0+**
- **Git** (for cloning repositories)

## Quick Start

### Option 1: Use Pre-built Libraries (Recommended for Development)

If you have access to pre-built ngtcp2 and OpenSSL libraries:

1. Place `libngtcp2.a` in `ios/libs/`
2. Place OpenSSL libraries (`libssl.a`, `libcrypto.a`) in `ios/libs/`
3. Place headers in `ios/include/ngtcp2/` and `ios/include/openssl/`
4. Update `MqttQuicPlugin.podspec` to link against these libraries

### Option 2: Build from Source

#### Step 1: Build OpenSSL for iOS

```bash
cd ios
./build-openssl.sh --arch arm64 --sdk iphoneos
```

This will:
- Clone OpenSSL (if not present)
- Build static libraries for iOS
- Install to `ios/install/openssl-ios/`

**Note:** For simulator builds, use:
```bash
./build-openssl.sh --arch x86_64 --sdk iphonesimulator
```

#### Step 2: Build ngtcp2 for iOS

```bash
cd ios
./build-ngtcp2.sh \
  --openssl-path ./install/openssl-ios \
  --arch arm64 \
  --sdk iphoneos
```

This will:
- Build ngtcp2 static library
- Link against OpenSSL
- Install to `ios/build/ios-arm64/install/`

#### Step 3: Build for Multiple Architectures

For a universal library (arm64 + x86_64 for simulator):

```bash
# Build for device (arm64)
./build-openssl.sh --arch arm64 --sdk iphoneos
./build-ngtcp2.sh --openssl-path ./install/openssl-ios --arch arm64 --sdk iphoneos

# Build for simulator (x86_64)
./build-openssl.sh --arch x86_64 --sdk iphonesimulator
./build-ngtcp2.sh --openssl-path ./install/openssl-ios --arch x86_64 --sdk iphonesimulator

# Create universal library
lipo -create \
  build/ios-arm64/install/lib/libngtcp2.a \
  build/ios-x86_64/install/lib/libngtcp2.a \
  -output libs/libngtcp2-universal.a
```

## Integration into Xcode Project

### Option A: CocoaPods (Recommended)

Update `ios/MqttQuicPlugin.podspec`:

```ruby
Pod::Spec.new do |s|
  # ... existing configuration ...
  
  # ngtcp2 static library
  s.vendored_libraries = 'libs/libngtcp2.a'
  
  # Header search paths
  s.public_header_files = 'Sources/**/*.h'
  s.private_header_files = 'Sources/**/*.h'
  s.header_mappings_dir = 'Sources'
  
  # Include ngtcp2 headers
  s.xcconfig = {
    'HEADER_SEARCH_PATHS' => '$(PODS_ROOT)/MqttQuicPlugin/include/ngtcp2 $(PODS_ROOT)/MqttQuicPlugin/include/openssl',
    'LIBRARY_SEARCH_PATHS' => '$(PODS_ROOT)/MqttQuicPlugin/libs',
    'OTHER_LDFLAGS' => '-lngtcp2 -lssl -lcrypto'
  }
  
  # OpenSSL dependency (if using CocoaPods)
  s.dependency 'OpenSSL-Universal', '~> 3.0'
end
```

### Option B: Manual Integration

1. Add `libngtcp2.a` to Xcode project
2. Add header search paths:
   - `$(SRCROOT)/../ios/include/ngtcp2`
   - `$(SRCROOT)/../ios/include/openssl`
3. Link against:
   - `libngtcp2.a`
   - `libssl.a` (OpenSSL)
   - `libcrypto.a` (OpenSSL)

## Using Pre-built Libraries

If you prefer to use pre-built libraries:

### OpenSSL

Download from:
- https://github.com/x2on/OpenSSL-for-iPhone
- https://github.com/krzyzanowskim/OpenSSL

### ngtcp2

Currently, there are no widely available pre-built ngtcp2 libraries for iOS. You'll need to build from source.

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

## Next Steps

After building ngtcp2:

1. Update `NGTCP2Client.swift` to implement the TODO sections
2. Replace `QuicClientStub` with `NGTCP2Client` in `MQTTClient.swift`
3. Test connection to MQTT server over QUIC

See `NGTCP2_INTEGRATION_PLAN.md` for detailed implementation guide.
