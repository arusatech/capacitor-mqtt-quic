#!/bin/bash
#
# Build script for ngtcp2 on iOS
# 
# This script builds ngtcp2 as a static library for iOS.
# It requires:
# - Xcode 14+ (for iOS 15+)
# - CMake 3.20+
# - iOS SDK 15.0+
# - OpenSSL 3.0+ (built for iOS)
#
# Usage:
#   ./build-ngtcp2.sh [--openssl-path PATH] [--arch ARCH] [--sdk SDK]
#
# Example:
#   ./build-ngtcp2.sh --openssl-path /path/to/openssl-ios --arch arm64 --sdk iphoneos
#

set -e

# Default values
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -z "$PROJECT_DIR" ] && [ -f "$SCRIPT_DIR/../package.json" ]; then
    PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
if [ -n "$PROJECT_DIR" ]; then
    REF_CODE_DIR="$(cd "$PROJECT_DIR/ref-code" && pwd)"
else
    if [ -d "$SCRIPT_DIR/../ref-code" ]; then
        REF_CODE_DIR="$(cd "$SCRIPT_DIR/../ref-code" && pwd)"
    else
        REF_CODE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
    fi
fi
NGTCP2_SOURCE_DIR="${NGTCP2_SOURCE_DIR:-$REF_CODE_DIR/ngtcp2}"
if [[ "$NGTCP2_SOURCE_DIR" != /* ]]; then
    NGTCP2_SOURCE_DIR="$REF_CODE_DIR/$NGTCP2_SOURCE_DIR"
fi
OPENSSL_PATH="${OPENSSL_PATH:-}"
USE_QUICTLS="${USE_QUICTLS:-0}"
ARCH="${ARCH:-arm64}"
SDK="${SDK:-iphoneos}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-15.0}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --openssl-path)
            OPENSSL_PATH="$2"
            shift 2
            ;;
        --quictls)
            USE_QUICTLS=1
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
            echo "Usage: $0 [--openssl-path PATH] [--arch ARCH] [--sdk SDK] [--quictls]"
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

# Check if ngtcp2 source exists
if [ ! -d "$NGTCP2_SOURCE_DIR" ]; then
    echo "Error: ngtcp2 source directory not found: $NGTCP2_SOURCE_DIR"
    echo "Please set NGTCP2_SOURCE_DIR environment variable or clone ngtcp2:"
    echo "  git clone https://github.com/ngtcp2/ngtcp2.git $NGTCP2_SOURCE_DIR"
    exit 1
fi

# Ensure required submodules are present (munit)
if [ ! -f "$NGTCP2_SOURCE_DIR/munit/munit.c" ]; then
    if [ -d "$NGTCP2_SOURCE_DIR/.git" ]; then
        echo "Initializing ngtcp2 submodules..."
        (cd "$NGTCP2_SOURCE_DIR" && git submodule update --init --recursive) || {
            echo "Error: Failed to initialize ngtcp2 submodules"
            exit 1
        }
    else
        echo "Warning: ngtcp2 submodules are missing (munit)"
        echo "Tests will be disabled, but if configuration still fails, clone with submodules:"
        echo "  git clone --recurse-submodules https://github.com/ngtcp2/ngtcp2.git $NGTCP2_SOURCE_DIR"
    fi
fi

# Check OpenSSL
if [ -z "$OPENSSL_PATH" ]; then
    if [ -d "$SCRIPT_DIR/install/openssl-ios" ]; then
        OPENSSL_PATH="$SCRIPT_DIR/install/openssl-ios"
    else
        echo "Warning: OpenSSL path not specified. ngtcp2 will be built without TLS support."
        echo "To build with OpenSSL, use: --openssl-path /path/to/openssl-ios"
        echo ""
        echo "You can build OpenSSL for iOS using:"
        echo "  git clone https://github.com/openssl/openssl.git"
        echo "  cd openssl"
        echo "  ./Configure ios64-cross --prefix=/tmp/openssl-ios no-shared no-tests"
        echo "  make -j\$(sysctl -n hw.ncpu)"
        echo "  make install"
        exit 1
    fi
fi

# Verify OpenSSL installation
if [[ "$OPENSSL_PATH" != /* ]]; then
    if [ -d "$SCRIPT_DIR/$OPENSSL_PATH" ]; then
        OPENSSL_PATH="$SCRIPT_DIR/$OPENSSL_PATH"
    elif [ -d "$REF_CODE_DIR/$OPENSSL_PATH" ]; then
        OPENSSL_PATH="$REF_CODE_DIR/$OPENSSL_PATH"
    fi
fi

if [ ! -d "$OPENSSL_PATH" ]; then
    echo "Error: OpenSSL path does not exist: $OPENSSL_PATH"
    exit 1
fi

# Check for required OpenSSL files
OPENSSL_LIB_DIR="$OPENSSL_PATH/lib"
OPENSSL_INCLUDE_DIR="$OPENSSL_PATH/include"
OPENSSL_CRYPTO_LIB="$OPENSSL_LIB_DIR/libcrypto.a"
OPENSSL_SSL_LIB="$OPENSSL_LIB_DIR/libssl.a"

if [ ! -f "$OPENSSL_CRYPTO_LIB" ]; then
    echo "Error: OpenSSL crypto library not found: $OPENSSL_CRYPTO_LIB"
    echo "Please ensure OpenSSL is built and installed correctly"
    exit 1
fi

if [ ! -f "$OPENSSL_SSL_LIB" ]; then
    echo "Error: OpenSSL SSL library not found: $OPENSSL_SSL_LIB"
    echo "Please ensure OpenSSL is built and installed correctly"
    exit 1
fi

if [ ! -d "$OPENSSL_INCLUDE_DIR" ]; then
    echo "Error: OpenSSL include directory not found: $OPENSSL_INCLUDE_DIR"
    echo "Please ensure OpenSSL is built and installed correctly"
    exit 1
fi

if [ "$USE_QUICTLS" = "1" ]; then
    if ! grep -q "SSL_provide_quic_data" "$OPENSSL_INCLUDE_DIR/openssl/ssl.h" 2>/dev/null; then
        echo "Error: OpenSSL headers at $OPENSSL_INCLUDE_DIR do not include QUIC APIs."
        echo "Rebuild OpenSSL with --quictls and ensure OPENSSL_SOURCE_DIR points to quictls."
        exit 1
    fi
fi

echo "  OpenSSL Path: $OPENSSL_PATH"
echo "  OpenSSL Libraries: $OPENSSL_LIB_DIR"
echo "  OpenSSL Headers: $OPENSSL_INCLUDE_DIR"

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
CMAKE_ARGS=(
    -DCMAKE_SYSTEM_NAME=iOS
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET"
    -DCMAKE_OSX_ARCHITECTURES="$ARCH"
    -DCMAKE_OSX_SYSROOT="$IOS_SDK_PATH"
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
    -DENABLE_LIB_ONLY=ON
    -DCMAKE_INSTALL_PREFIX="$(pwd)/install"
    -DENABLE_TESTS=OFF
    -DENABLE_EXAMPLES=OFF
)

if [ -n "$OPENSSL_PATH" ]; then
    # CMake's FindOpenSSL needs explicit paths
    CMAKE_ARGS+=(
        -DENABLE_OPENSSL=ON
        -DOPENSSL_ROOT_DIR="$OPENSSL_PATH"
        -DOPENSSL_CRYPTO_LIBRARY="$OPENSSL_CRYPTO_LIB"
        -DOPENSSL_SSL_LIBRARY="$OPENSSL_SSL_LIB"
        -DOPENSSL_INCLUDE_DIR="$OPENSSL_INCLUDE_DIR"
        -DOPENSSL_LIBRARIES="$OPENSSL_SSL_LIB;$OPENSSL_CRYPTO_LIB"
    )

    if [ "$USE_QUICTLS" = "1" ]; then
        CMAKE_ARGS+=(
            -DENABLE_QUICTLS=ON
        )
    fi
else
    CMAKE_ARGS+=(
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

echo ""
echo "Build complete!"
echo "Static library: $(pwd)/install/lib/libngtcp2.a"
echo "Headers: $(pwd)/install/include"
