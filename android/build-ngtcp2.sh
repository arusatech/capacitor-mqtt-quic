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
#   ./build-ngtcp2.sh [--ndk-path PATH] [--abi ABI] [--platform PLATFORM]
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
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--ndk-path PATH] [--abi ABI] [--platform PLATFORM]"
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
    # Try common locations
    if [ -d "$HOME/Android/Sdk/ndk" ]; then
        # Find latest NDK version
        LATEST_NDK=$(ls -d "$HOME/Android/Sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1)
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

# Check if ngtcp2 source exists
NGTCP2_SOURCE_DIR="${NGTCP2_SOURCE_DIR:-../../ngtcp2}"
if [ ! -d "$NGTCP2_SOURCE_DIR" ]; then
    echo "Error: ngtcp2 source directory not found: $NGTCP2_SOURCE_DIR"
    echo "Please set NGTCP2_SOURCE_DIR environment variable or clone ngtcp2:"
    echo "  git clone https://github.com/ngtcp2/ngtcp2.git $NGTCP2_SOURCE_DIR"
    exit 1
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
cd "$BUILD_DIR"

# Configure CMake
CMAKE_ARGS=(
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK/build/cmake/android.toolchain.cmake"
    -DANDROID_ABI="$ANDROID_ABI"
    -DANDROID_PLATFORM="$ANDROID_PLATFORM"
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
    -DENABLE_LIB_ONLY=ON
)

if [ -n "$OPENSSL_PATH" ]; then
    CMAKE_ARGS+=(
        -DENABLE_OPENSSL=ON
        -DOPENSSL_ROOT_DIR="$OPENSSL_PATH"
    )
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
echo "Library: $(pwd)/install/lib/libngtcp2.a"
echo "Headers: $(pwd)/install/include"
