#!/bin/bash
#
# Build script for ngtcp2 on Android
#
# This script builds ngtcp2 as a native library for Android using NDK.
# It requires:
# - Android NDK r25+
# - CMake 3.20+
# - OpenSSL 3.0+ (built for Android)
#
# Usage:
#   ./build-ngtcp2.sh [--ndk-path PATH] [--abi ABI] [--platform PLATFORM] [--openssl-path PATH] [--prefix PATH] [--quictls]
#
# Example:
#   ./build-ngtcp2.sh --ndk-path ~/Android/Sdk/ndk/25.2.9519653 --abi arm64-v8a --platform android-21
#

set -e

# Default values
ANDROID_NDK="${ANDROID_NDK:-}"
ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-21}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
OPENSSL_PATH="${OPENSSL_PATH:-}"
USE_QUICTLS="${USE_QUICTLS:-0}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -n "$PROJECT_DIR" ]; then
    # PROJECT_DIR is the capacitor-mqtt-quic repo root
    REF_CODE_DIR="$(cd "$PROJECT_DIR/ref-code" && pwd)"
else
    # Fallback: repo root is one level above android/
    REF_CODE_DIR="$(cd "$SCRIPT_DIR/../ref-code" && pwd)"
fi
INSTALL_PREFIX="${INSTALL_PREFIX:-$SCRIPT_DIR/install/ngtcp2-android}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --ndk-path)
            ANDROID_NDK="$2"
            shift 2
            ;;
        --abi)
            ANDROID_ABI="$2"
            shift 2
            ;;
        --platform)
            ANDROID_PLATFORM="$2"
            shift 2
            ;;
        --build-type)
            BUILD_TYPE="$2"
            shift 2
            ;;
        --openssl-path)
            OPENSSL_PATH="$2"
            shift 2
            ;;
        --prefix)
            INSTALL_PREFIX="$2"
            shift 2
            ;;
        --quictls)
            USE_QUICTLS=1
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--ndk-path PATH] [--abi ABI] [--platform PLATFORM] [--openssl-path PATH] [--prefix PATH] [--quictls]"
            exit 1
            ;;
    esac
done

# Check prerequisites
if ! command -v cmake &> /dev/null; then
    echo "Error: CMake is not installed. Please install CMake 3.20+"
    exit 1
fi

# Find Android NDK
if [ -z "$ANDROID_NDK" ]; then
    # Try common locations (macOS + Linux)
    if [ -d "$HOME/Android/Sdk/ndk" ]; then
        # Find latest NDK version
        LATEST_NDK=$(ls -d "$HOME/Android/Sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1)
        if [ -n "$LATEST_NDK" ]; then
            ANDROID_NDK="$LATEST_NDK"
        fi
    elif [ -d "$HOME/Library/Android/sdk/ndk" ]; then
        LATEST_NDK=$(ls -d "$HOME/Library/Android/sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1)
        if [ -n "$LATEST_NDK" ]; then
            ANDROID_NDK="$LATEST_NDK"
        fi
    fi
    
    if [ -z "$ANDROID_NDK" ]; then
        echo "Error: Android NDK not found. Please specify --ndk-path"
        echo "Or set ANDROID_NDK environment variable"
        exit 1
    fi
fi

if [ ! -d "$ANDROID_NDK" ]; then
    echo "Error: Android NDK directory not found: $ANDROID_NDK"
    exit 1
fi

echo "Building ngtcp2 for Android"
echo "  NDK Path: $ANDROID_NDK"
echo "  ABI: $ANDROID_ABI"
echo "  Platform: $ANDROID_PLATFORM"
echo "  Build Type: $BUILD_TYPE"
if [[ "$INSTALL_PREFIX" != *"/$ANDROID_ABI" ]]; then
    INSTALL_PREFIX="$INSTALL_PREFIX/$ANDROID_ABI"
fi
echo "  Install Prefix: $INSTALL_PREFIX"

# Check if ngtcp2 source exists
if [ -n "$NGTCP2_SOURCE_DIR" ]; then
    if [[ "$NGTCP2_SOURCE_DIR" != /* ]]; then
        NGTCP2_SOURCE_DIR="$REF_CODE_DIR/$NGTCP2_SOURCE_DIR"
    fi
else
    NGTCP2_SOURCE_DIR="$REF_CODE_DIR/ngtcp2"
fi
if [ ! -d "$NGTCP2_SOURCE_DIR" ] && [ -d "$REF_CODE_DIR/ngtcp2" ]; then
    echo "Warning: NGTCP2_SOURCE_DIR not found; using $REF_CODE_DIR/ngtcp2"
    NGTCP2_SOURCE_DIR="$REF_CODE_DIR/ngtcp2"
fi
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
    echo "Warning: OpenSSL path not specified. ngtcp2 will be built without TLS support."
    echo "To build with OpenSSL, use: --openssl-path /path/to/openssl-android"
    echo ""
    echo "You can build OpenSSL for Android using build-openssl.sh"
fi

# Create build directory
BUILD_DIR="build/android-$ANDROID_ABI"
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
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK/build/cmake/android.toolchain.cmake"
    -DANDROID_ABI="$ANDROID_ABI"
    -DANDROID_PLATFORM="$ANDROID_PLATFORM"
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
    -DENABLE_LIB_ONLY=ON
    -DENABLE_TESTS=OFF
    -DENABLE_EXAMPLES=OFF
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX"
)

if [ -n "$OPENSSL_PATH" ]; then
    if [[ "$OPENSSL_PATH" != /* ]]; then
        if [ -d "$SCRIPT_DIR/$OPENSSL_PATH" ]; then
            OPENSSL_PATH="$SCRIPT_DIR/$OPENSSL_PATH"
        else
            OPENSSL_PATH="$REF_CODE_DIR/$OPENSSL_PATH"
        fi
    fi
    # If ABI-aware install exists, prefer it
    if [ -d "$OPENSSL_PATH/$ANDROID_ABI" ]; then
        OPENSSL_PATH="$OPENSSL_PATH/$ANDROID_ABI"
    fi
    if [ ! -d "$OPENSSL_PATH" ]; then
        echo "Error: OpenSSL path does not exist: $OPENSSL_PATH"
        exit 1
    fi
    OPENSSL_PATH="$(cd "$OPENSSL_PATH" && pwd)"
    OPENSSL_LIB_DIR="$OPENSSL_PATH/lib"
    OPENSSL_INCLUDE_DIR="$OPENSSL_PATH/include"
    OPENSSL_CRYPTO_LIB="$OPENSSL_LIB_DIR/libcrypto.a"
    OPENSSL_SSL_LIB="$OPENSSL_LIB_DIR/libssl.a"

    if [ ! -f "$OPENSSL_CRYPTO_LIB" ] || [ ! -f "$OPENSSL_SSL_LIB" ]; then
        echo "Error: OpenSSL static libraries not found in $OPENSSL_LIB_DIR"
        exit 1
    fi
    if [ ! -d "$OPENSSL_INCLUDE_DIR" ]; then
        echo "Error: OpenSSL include directory not found: $OPENSSL_INCLUDE_DIR"
        exit 1
    fi

    if [ "$USE_QUICTLS" = "1" ]; then
        if ! grep -q "SSL_provide_quic_data" "$OPENSSL_INCLUDE_DIR/openssl/ssl.h" 2>/dev/null; then
            echo "OpenSSL headers at $OPENSSL_INCLUDE_DIR do not include QUIC APIs."
            if [ -x "$SCRIPT_DIR/build-openssl.sh" ]; then
                echo "Attempting to rebuild OpenSSL via build-openssl.sh..."
                OPENSSL_PREFIX="$OPENSSL_PATH"
                if [[ "$OPENSSL_PREFIX" == *"/$ANDROID_ABI" ]]; then
                    OPENSSL_PREFIX="${OPENSSL_PREFIX%/$ANDROID_ABI}"
                fi
                "$SCRIPT_DIR/build-openssl.sh" \
                    --ndk-path "$ANDROID_NDK" \
                    --abi "$ANDROID_ABI" \
                    --platform "$ANDROID_PLATFORM" \
                    --quictls \
                    --prefix "$OPENSSL_PREFIX" || {
                    echo "Error: OpenSSL rebuild failed."
                    exit 1
                }
                if ! grep -q "SSL_provide_quic_data" "$OPENSSL_INCLUDE_DIR/openssl/ssl.h" 2>/dev/null; then
                    echo "Error: OpenSSL headers at $OPENSSL_INCLUDE_DIR still do not include QUIC APIs."
                    echo "Ensure OPENSSL_SOURCE_DIR points to a quictls checkout."
                    exit 1
                fi
            else
                echo "Error: OpenSSL headers at $OPENSSL_INCLUDE_DIR do not include QUIC APIs."
                echo "Rebuild OpenSSL with --quictls and ensure OPENSSL_SOURCE_DIR points to quictls."
                exit 1
            fi
        fi
    fi

    CMAKE_ARGS+=(
        -DENABLE_OPENSSL=ON
        -DOPENSSL_ROOT_DIR="$OPENSSL_PATH"
        -DOPENSSL_INCLUDE_DIR="$OPENSSL_INCLUDE_DIR"
        -DOPENSSL_CRYPTO_LIBRARY="$OPENSSL_CRYPTO_LIB"
        -DOPENSSL_SSL_LIBRARY="$OPENSSL_SSL_LIB"
        -DOPENSSL_LIBRARIES="$OPENSSL_SSL_LIB;$OPENSSL_CRYPTO_LIB"
    )

    if [ "$USE_QUICTLS" = "1" ]; then
        CMAKE_ARGS+=(
            -DENABLE_QUICTLS=ON
            -DHAVE_SSL_PROVIDE_QUIC_DATA=1
            -DHAVE_SSL_SET_QUIC_TLS_CBS=0
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
cmake --build . --config "$BUILD_TYPE" -j$(nproc 2>/dev/null || sysctl -n hw.ncpu)

echo ""
echo "Installing..."
cmake --install .

echo ""
echo "Build complete!"
echo "Library: $INSTALL_PREFIX/lib/libngtcp2.a"
echo "Headers: $INSTALL_PREFIX/include"
