#!/bin/bash
#
# Build script for nghttp3 on Android
#
# This script builds nghttp3 as a static library for Android using NDK.
# It requires:
# - Android NDK r25+
# - CMake 3.20+
#
# Usage:
#   ./build-nghttp3.sh [--ndk-path PATH] [--abi ABI] [--platform PLATFORM] [--prefix PATH]
#
# Example:
#   ./build-nghttp3.sh --ndk-path ~/Android/Sdk/ndk/25.2.9519653 --abi arm64-v8a --platform android-21
#

set -e

# Default values
ANDROID_NDK="${ANDROID_NDK:-}"
ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-21}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -n "$PROJECT_DIR" ]; then
    REF_CODE_DIR="$(cd "$PROJECT_DIR/ref-code" && pwd)"
else
    REF_CODE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi
INSTALL_PREFIX="${INSTALL_PREFIX:-$SCRIPT_DIR/install/nghttp3-android}"

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
        --prefix)
            INSTALL_PREFIX="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--ndk-path PATH] [--abi ABI] [--platform PLATFORM] [--prefix PATH]"
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
    if [ -d "$HOME/Android/Sdk/ndk" ]; then
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

echo "Building nghttp3 for Android"
echo "  NDK Path: $ANDROID_NDK"
echo "  ABI: $ANDROID_ABI"
echo "  Platform: $ANDROID_PLATFORM"
echo "  Build Type: $BUILD_TYPE"
if [[ "$INSTALL_PREFIX" != *"/$ANDROID_ABI" ]]; then
    INSTALL_PREFIX="$INSTALL_PREFIX/$ANDROID_ABI"
fi
echo "  Install Prefix: $INSTALL_PREFIX"

# Check if nghttp3 source exists
if [ -n "$NGHTTP3_SOURCE_DIR" ]; then
    if [[ "$NGHTTP3_SOURCE_DIR" != /* ]]; then
        NGHTTP3_SOURCE_DIR="$REF_CODE_DIR/$NGHTTP3_SOURCE_DIR"
    fi
else
    NGHTTP3_SOURCE_DIR="$REF_CODE_DIR/nghttp3"
fi
if [ ! -d "$NGHTTP3_SOURCE_DIR" ] && [ -d "$REF_CODE_DIR/nghttp3" ]; then
    echo "Warning: NGHTTP3_SOURCE_DIR not found; using $REF_CODE_DIR/nghttp3"
    NGHTTP3_SOURCE_DIR="$REF_CODE_DIR/nghttp3"
fi
if [ ! -d "$NGHTTP3_SOURCE_DIR" ]; then
    echo "Error: nghttp3 source directory not found: $NGHTTP3_SOURCE_DIR"
    echo "Please set NGHTTP3_SOURCE_DIR environment variable or clone nghttp3:"
    echo "  git clone --recurse-submodules https://github.com/ngtcp2/nghttp3.git $NGHTTP3_SOURCE_DIR"
    exit 1
fi

# Ensure required submodules are present (sfparse, munit)
if [ ! -f "$NGHTTP3_SOURCE_DIR/sfparse/sfparse.c" ] || [ ! -f "$NGHTTP3_SOURCE_DIR/munit/munit.c" ]; then
    if [ -d "$NGHTTP3_SOURCE_DIR/.git" ]; then
        echo "Initializing nghttp3 submodules..."
        (cd "$NGHTTP3_SOURCE_DIR" && git submodule update --init --recursive) || {
            echo "Error: Failed to initialize nghttp3 submodules"
            exit 1
        }
    else
        echo "Error: nghttp3 submodules are missing (sfparse/munit)"
        echo "Please clone with submodules:"
        echo "  git clone --recurse-submodules https://github.com/ngtcp2/nghttp3.git $NGHTTP3_SOURCE_DIR"
        echo "Or if already cloned:"
        echo "  cd $NGHTTP3_SOURCE_DIR && git submodule update --init --recursive"
        exit 1
    fi
fi

# Create build directory
BUILD_DIR="build/nghttp3-android-$ANDROID_ABI"
mkdir -p "$BUILD_DIR"

# Clean build dir if CMake cache points to a different source tree
if [ -f "$BUILD_DIR/CMakeCache.txt" ]; then
    CMAKE_HOME_DIR=$(grep "^CMAKE_HOME_DIRECTORY:INTERNAL=" "$BUILD_DIR/CMakeCache.txt" | cut -d= -f2-)
    if [ -n "$CMAKE_HOME_DIR" ] && [ "$CMAKE_HOME_DIR" != "$NGHTTP3_SOURCE_DIR" ]; then
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
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX"
)

echo ""
echo "Configuring CMake..."
cmake "$NGHTTP3_SOURCE_DIR" "${CMAKE_ARGS[@]}"

echo ""
echo "Building nghttp3..."
cmake --build . --config "$BUILD_TYPE" -j$(nproc 2>/dev/null || sysctl -n hw.ncpu)

echo ""
echo "Installing..."
cmake --install .

echo ""
echo "Build complete!"
echo "Library: $INSTALL_PREFIX/lib/libnghttp3.a"
echo "Headers: $INSTALL_PREFIX/include"
