#!/bin/bash
#
# Build script for ngtcp2 on iOS
# Builds ngtcp2 as a static library for iOS.
# Default TLS backend: WolfSSL (TLS 1.3 + QUIC). Set USE_WOLFSSL=0 or use --quictls for QuicTLS.
# Usage:
#   ./build-ngtcp2.sh [--wolfssl-path PATH] [--openssl-path PATH] [--arch ARCH] [--sdk SDK]
# Example (default WolfSSL): ./build-ngtcp2.sh   # uses ios/install/wolfssl-ios when USE_WOLFSSL=1
# Example (QuicTLS): ./build-ngtcp2.sh --openssl-path ./install/openssl-ios --quictls
#

set -e

# Default values: PROJECT_DIR = plugin root (where build-native.sh lives)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -z "$PROJECT_DIR" ]; then
    PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
DEPS_DIR="${PROJECT_DIR}/deps"
[ -f "$PROJECT_DIR/deps-versions.sh" ] && . "$PROJECT_DIR/deps-versions.sh"
NGTCP2_SOURCE_DIR="${NGTCP2_SOURCE_DIR:-${DEPS_DIR}/ngtcp2}"
if [[ "$NGTCP2_SOURCE_DIR" != /* ]]; then
    NGTCP2_SOURCE_DIR="${DEPS_DIR}/$NGTCP2_SOURCE_DIR"
fi
WOLFSSL_PATH="${WOLFSSL_PATH:-}"
OPENSSL_PATH="${OPENSSL_PATH:-}"
USE_WOLFSSL="${USE_WOLFSSL:-1}"
USE_QUICTLS="${USE_QUICTLS:-1}"
ARCH="${ARCH:-arm64}"
SDK="${SDK:-iphoneos}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-15.0}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --wolfssl-path)
            WOLFSSL_PATH="$2"
            USE_WOLFSSL=1
            shift 2
            ;;
        --openssl-path)
            OPENSSL_PATH="$2"
            shift 2
            ;;
        --quictls)
            USE_QUICTLS=1
            USE_WOLFSSL=0
            shift
            ;;
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --sdk)
            SDK="$2"
            shift 2
            ;;
        --build-type)
            BUILD_TYPE="$2"
            shift 2
            ;;
        --ios-deployment-target)
            IOS_DEPLOYMENT_TARGET="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--wolfssl-path PATH] [--openssl-path PATH] [--arch ARCH] [--sdk SDK] [--quictls]"
            exit 1
            ;;
    esac
done

# Check prerequisites
if ! command -v cmake &> /dev/null; then
    echo "Error: CMake is not installed. Please install CMake 3.20+"
    exit 1
fi

if ! command -v xcrun &> /dev/null; then
    echo "Error: Xcode command line tools are not installed"
    exit 1
fi

# Get iOS SDK path
IOS_SDK_PATH=$(xcrun --sdk "$SDK" --show-sdk-path)
if [ -z "$IOS_SDK_PATH" ]; then
    echo "Error: Could not find iOS SDK for $SDK"
    exit 1
fi

echo "Building ngtcp2 for iOS"
echo "  Architecture: $ARCH"
echo "  SDK: $SDK"
echo "  SDK Path: $IOS_SDK_PATH"
echo "  Build Type: $BUILD_TYPE"
echo "  Deployment Target: iOS $IOS_DEPLOYMENT_TARGET"

# Clone ngtcp2 if missing (URL from deps-versions.sh / ref-code/VERSION.txt)
NGTCP2_REPO_URL="${NGTCP2_REPO_URL:-https://github.com/ngtcp2/ngtcp2.git}"
if [ ! -d "$NGTCP2_SOURCE_DIR" ]; then
    echo "ngtcp2 source not found. Cloning into $NGTCP2_SOURCE_DIR ..."
    mkdir -p "$DEPS_DIR"
    git clone --recurse-submodules "$NGTCP2_REPO_URL" "$NGTCP2_SOURCE_DIR" || {
        echo "Error: Failed to clone ngtcp2"
        exit 1
    }
fi
if [ -n "$NGTCP2_COMMIT" ] && [ -d "$NGTCP2_SOURCE_DIR/.git" ]; then
    echo "Pinning ngtcp2 to commit $NGTCP2_COMMIT"
    (cd "$NGTCP2_SOURCE_DIR" && git fetch origin "$NGTCP2_COMMIT" 2>/dev/null; git checkout "$NGTCP2_COMMIT") || {
        echo "Error: Failed to checkout ngtcp2 commit $NGTCP2_COMMIT"
        exit 1
    }
fi

# Ensure required sources are present (munit: top-level or tests/munit)
if [ ! -f "$NGTCP2_SOURCE_DIR/munit/munit.c" ] && [ ! -f "$NGTCP2_SOURCE_DIR/tests/munit/munit.c" ]; then
    if [ -d "$NGTCP2_SOURCE_DIR/.git" ]; then
        echo "Initializing ngtcp2 submodules..."
        (cd "$NGTCP2_SOURCE_DIR" && git submodule update --init --recursive) || {
            echo "Error: Failed to initialize ngtcp2 submodules"
            exit 1
        }
    else
        echo "Warning: ngtcp2 submodules are missing (munit)"
        echo "Tests will be disabled, but if configuration still fails, clone with submodules:"
        echo "  git clone --recurse-submodules $NGTCP2_REPO_URL $NGTCP2_SOURCE_DIR"
    fi
fi

# Prefer WolfSSL (TLS 1.3 + QUIC) when USE_WOLFSSL=1
if [ "$USE_WOLFSSL" = "1" ] && [ -z "$WOLFSSL_PATH" ]; then
    if [ -d "$SCRIPT_DIR/install/wolfssl-ios" ]; then
        WOLFSSL_PATH="$SCRIPT_DIR/install/wolfssl-ios"
    fi
fi
if [ -z "$WOLFSSL_PATH" ] && [ -z "$OPENSSL_PATH" ]; then
    if [ -d "$SCRIPT_DIR/install/openssl-ios" ]; then
        OPENSSL_PATH="$SCRIPT_DIR/install/openssl-ios"
    else
        echo "Error: No TLS path. Build WolfSSL or OpenSSL first."
        echo "  WolfSSL: ./build-wolfssl.sh  then  ./build-ngtcp2.sh --wolfssl-path ./install/wolfssl-ios"
        echo "  QuicTLS: ./build-openssl.sh  then  ./build-ngtcp2.sh --openssl-path ./install/openssl-ios --quictls"
        exit 1
    fi
fi

# Resolve WolfSSL path and verify
if [ -n "$WOLFSSL_PATH" ]; then
    [[ "$WOLFSSL_PATH" != /* ]] && [ -d "$SCRIPT_DIR/$WOLFSSL_PATH" ] && WOLFSSL_PATH="$SCRIPT_DIR/$WOLFSSL_PATH"
    [[ "$WOLFSSL_PATH" != /* ]] && [ -d "$DEPS_DIR/$WOLFSSL_PATH" ] && WOLFSSL_PATH="$DEPS_DIR/$WOLFSSL_PATH"
    if [ ! -d "$WOLFSSL_PATH" ]; then
        echo "Error: WolfSSL path does not exist: $WOLFSSL_PATH"
        exit 1
    fi
    WOLFSSL_LIB="$WOLFSSL_PATH/lib/libwolfssl.a"
    WOLFSSL_INCLUDE_DIR="$WOLFSSL_PATH/include"
    if [ ! -f "$WOLFSSL_LIB" ]; then
        echo "Error: WolfSSL library not found: $WOLFSSL_LIB"
        exit 1
    fi
    if [ ! -d "$WOLFSSL_INCLUDE_DIR/wolfssl" ]; then
        echo "Error: WolfSSL headers not found: $WOLFSSL_INCLUDE_DIR/wolfssl"
        exit 1
    fi
    echo "  TLS: WolfSSL (TLS 1.3 + QUIC)"
    echo "  WolfSSL Path: $WOLFSSL_PATH"
fi

# Resolve OpenSSL path and verify (when not using WolfSSL)
if [ -n "$OPENSSL_PATH" ]; then
    [[ "$OPENSSL_PATH" != /* ]] && [ -d "$SCRIPT_DIR/$OPENSSL_PATH" ] && OPENSSL_PATH="$SCRIPT_DIR/$OPENSSL_PATH"
    [[ "$OPENSSL_PATH" != /* ]] && [ -d "$DEPS_DIR/$OPENSSL_PATH" ] && OPENSSL_PATH="$DEPS_DIR/$OPENSSL_PATH"
    if [ ! -d "$OPENSSL_PATH" ]; then
        echo "Error: OpenSSL path does not exist: $OPENSSL_PATH"
        exit 1
    fi
    OPENSSL_LIB_DIR="$OPENSSL_PATH/lib"
    OPENSSL_INCLUDE_DIR="$OPENSSL_PATH/include"
    OPENSSL_CRYPTO_LIB="$OPENSSL_LIB_DIR/libcrypto.a"
    OPENSSL_SSL_LIB="$OPENSSL_LIB_DIR/libssl.a"
    if [ ! -f "$OPENSSL_CRYPTO_LIB" ] || [ ! -f "$OPENSSL_SSL_LIB" ]; then
        echo "Error: OpenSSL libraries not found in $OPENSSL_PATH"
        exit 1
    fi
    if [ "$USE_QUICTLS" = "1" ]; then
        if ! grep -q "SSL_provide_quic_data" "$OPENSSL_INCLUDE_DIR/openssl/ssl.h" 2>/dev/null; then
            echo "Error: OpenSSL at $OPENSSL_INCLUDE_DIR does not include QUIC APIs (use QuicTLS)."
            exit 1
        fi
    fi
    echo "  TLS: OpenSSL/QuicTLS"
    echo "  OpenSSL Path: $OPENSSL_PATH"
fi

# Create build directory
BUILD_DIR="build/ios-$ARCH"
mkdir -p "$BUILD_DIR"

# Clean build dir if CMake cache points to a different source tree
if [ -f "$BUILD_DIR/CMakeCache.txt" ]; then
    CMAKE_HOME_DIR=$(grep "^CMAKE_HOME_DIRECTORY:INTERNAL=" "$BUILD_DIR/CMakeCache.txt" | cut -d= -f2-)
    if [ -n "$CMAKE_HOME_DIR" ] && [ "$CMAKE_HOME_DIR" != "$NGTCP2_SOURCE_DIR" ]; then
        echo "CMake cache source mismatch. Cleaning $BUILD_DIR"
        rm -rf "$BUILD_DIR"
        mkdir -p "$BUILD_DIR"
    fi
fi

cd "$BUILD_DIR"

# Configure CMake
# Build static libs only; shared dylib would need Security/CoreFoundation for WolfSSL's ProcessPeerCerts on iOS
CMAKE_ARGS=(
    -DCMAKE_SYSTEM_NAME=iOS
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET"
    -DCMAKE_OSX_ARCHITECTURES="$ARCH"
    -DCMAKE_OSX_SYSROOT="$IOS_SDK_PATH"
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
    -DENABLE_LIB_ONLY=ON
    -DENABLE_SHARED_LIB=OFF
    -DENABLE_STATIC_LIB=ON
    -DCMAKE_INSTALL_PREFIX="$(pwd)/install"
    -DENABLE_TESTS=OFF
    -DENABLE_EXAMPLES=OFF
)

if [ -n "$WOLFSSL_PATH" ]; then
    CMAKE_ARGS+=(
        -DENABLE_WOLFSSL=ON
        -DENABLE_OPENSSL=OFF
        -DWOLFSSL_INCLUDE_DIR="$WOLFSSL_INCLUDE_DIR"
        -DWOLFSSL_LIBRARY="$WOLFSSL_LIB"
    )
elif [ -n "$OPENSSL_PATH" ]; then
    CMAKE_ARGS+=(
        -DENABLE_WOLFSSL=OFF
        -DENABLE_OPENSSL=ON
        -DOPENSSL_ROOT_DIR="$OPENSSL_PATH"
        -DOPENSSL_CRYPTO_LIBRARY="$OPENSSL_CRYPTO_LIB"
        -DOPENSSL_SSL_LIBRARY="$OPENSSL_SSL_LIB"
        -DOPENSSL_INCLUDE_DIR="$OPENSSL_INCLUDE_DIR"
        -DOPENSSL_LIBRARIES="$OPENSSL_SSL_LIB;$OPENSSL_CRYPTO_LIB"
    )
    [ "$USE_QUICTLS" = "1" ] && CMAKE_ARGS+=( -DENABLE_QUICTLS=ON )
else
    CMAKE_ARGS+=(
        -DENABLE_WOLFSSL=OFF
        -DENABLE_OPENSSL=OFF
    )
fi

echo ""
echo "Configuring CMake..."
cmake "$NGTCP2_SOURCE_DIR" "${CMAKE_ARGS[@]}"

echo ""
echo "Building ngtcp2..."
cmake --build . --config "$BUILD_TYPE" -j$(sysctl -n hw.ncpu)

echo ""
echo "Installing..."
cmake --install .

echo ""
echo "Syncing artifacts to ios/libs and ios/include..."
LIBS_DIR="$SCRIPT_DIR/libs"
INCLUDE_DIR="$SCRIPT_DIR/include"
mkdir -p "$LIBS_DIR" "$INCLUDE_DIR"
cp "$(pwd)/install/lib/libngtcp2.a" "$LIBS_DIR/"
for crypto_lib in "$(pwd)/install/lib"/libngtcp2_crypto_*.a; do
    if [ -f "$crypto_lib" ]; then
        cp "$crypto_lib" "$LIBS_DIR/"
    fi
done
if [ -d "$(pwd)/install/include/ngtcp2" ]; then
    cp -R "$(pwd)/install/include/ngtcp2" "$INCLUDE_DIR/"
fi
# When using WolfSSL, ensure libwolfssl.a is in libs (for xcframework)
if [ -n "$WOLFSSL_PATH" ] && [ -f "$WOLFSSL_PATH/lib/libwolfssl.a" ]; then
    cp -f "$WOLFSSL_PATH/lib/libwolfssl.a" "$LIBS_DIR/"
    [ -d "$WOLFSSL_PATH/include/wolfssl" ] && rm -rf "$INCLUDE_DIR/wolfssl"; cp -R "$WOLFSSL_PATH/include/wolfssl" "$INCLUDE_DIR/"
fi

echo ""
echo "Build complete!"
echo "Static library: $(pwd)/install/lib/libngtcp2.a"
echo "Crypto: libngtcp2_crypto_wolfssl.a or libngtcp2_crypto_quictls.a"
echo "Headers: $(pwd)/install/include"
