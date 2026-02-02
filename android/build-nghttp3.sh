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

# Default values: PROJECT_DIR = plugin root (where build-native.sh lives)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -z "$PROJECT_DIR" ]; then
    PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
DEPS_DIR="${PROJECT_DIR}/deps"
[ -f "$PROJECT_DIR/deps-versions.sh" ] && . "$PROJECT_DIR/deps-versions.sh"
ANDROID_NDK="${ANDROID_NDK:-}"
ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-21}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
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

# Resolve nghttp3 source dir (default: deps/nghttp3); URL from deps-versions.sh / ref-code/VERSION.txt
NGHTTP3_SOURCE_DIR="${NGHTTP3_SOURCE_DIR:-${DEPS_DIR}/nghttp3}"
if [[ "$NGHTTP3_SOURCE_DIR" != /* ]]; then
    NGHTTP3_SOURCE_DIR="${DEPS_DIR}/$NGHTTP3_SOURCE_DIR"
fi
NGHTTP3_REPO_URL="${NGHTTP3_REPO_URL:-https://github.com/ngtcp2/nghttp3.git}"
# Clone nghttp3 if missing
if [ ! -d "$NGHTTP3_SOURCE_DIR" ]; then
    echo "nghttp3 source not found. Cloning into $NGHTTP3_SOURCE_DIR ..."
    mkdir -p "$DEPS_DIR"
    git clone --recurse-submodules "$NGHTTP3_REPO_URL" "$NGHTTP3_SOURCE_DIR" || {
        echo "Error: Failed to clone nghttp3"
        exit 1
    }
fi
if [ -n "$NGHTTP3_COMMIT" ] && [ -d "$NGHTTP3_SOURCE_DIR/.git" ]; then
    echo "Pinning nghttp3 to commit $NGHTTP3_COMMIT"
    (cd "$NGHTTP3_SOURCE_DIR" && git fetch origin "$NGHTTP3_COMMIT" 2>/dev/null; git checkout "$NGHTTP3_COMMIT") || {
        echo "Error: Failed to checkout nghttp3 commit $NGHTTP3_COMMIT"
        exit 1
    }
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
        echo "  git clone --recurse-submodules $NGHTTP3_REPO_URL $NGHTTP3_SOURCE_DIR"
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
