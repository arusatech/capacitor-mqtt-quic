#!/bin/bash
#
# Build script for nghttp3 on iOS
#
# This script builds nghttp3 as a static library for iOS.
# It requires:
# - Xcode 14+ (for iOS 15+)
# - CMake 3.20+
# - iOS SDK 15.0+
#
# Usage:
#   ./build-nghttp3.sh [--arch ARCH] [--sdk SDK]
#
# Example:
#   ./build-nghttp3.sh --arch arm64 --sdk iphoneos
#

set -e

# Default values
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -z "$PROJECT_DIR" ] && [ -f "$SCRIPT_DIR/../package.json" ]; then
    PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
if [ -n "$PROJECT_DIR" ]; then
    if [ -d "$PROJECT_DIR/ref-code" ]; then
        REF_CODE_DIR="$(cd "$PROJECT_DIR/ref-code" && pwd)"
    else
        # Plugin run from repo: use parent as ref-code (e.g. ref-code/capacitor-mqtt-quic -> ref-code)
        REF_CODE_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
    fi
else
    if [ -d "$SCRIPT_DIR/../ref-code" ]; then
        REF_CODE_DIR="$(cd "$SCRIPT_DIR/../ref-code" && pwd)"
    else
        REF_CODE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
    fi
fi
NGHTTP3_SOURCE_DIR="${NGHTTP3_SOURCE_DIR:-$REF_CODE_DIR/nghttp3}"
if [[ "$NGHTTP3_SOURCE_DIR" != /* ]]; then
    NGHTTP3_SOURCE_DIR="$REF_CODE_DIR/$NGHTTP3_SOURCE_DIR"
fi
# If default path does not exist, try sibling ref-code/nghttp3 (e.g. when plugin has ref-code/ but nghttp3 lives in repo ref-code/)
if [ -n "$PROJECT_DIR" ] && [ ! -d "$NGHTTP3_SOURCE_DIR" ] && [ -d "$(cd "$PROJECT_DIR/.." && pwd)/nghttp3" ]; then
    NGHTTP3_SOURCE_DIR="$(cd "$PROJECT_DIR/../nghttp3" && pwd)"
fi
ARCH="${ARCH:-arm64}"
SDK="${SDK:-iphoneos}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-15.0}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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
            echo "Usage: $0 [--arch ARCH] [--sdk SDK]"
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

echo "Building nghttp3 for iOS"
echo "  Architecture: $ARCH"
echo "  SDK: $SDK"
echo "  SDK Path: $IOS_SDK_PATH"
echo "  Build Type: $BUILD_TYPE"
echo "  Deployment Target: iOS $IOS_DEPLOYMENT_TARGET"

# Check if nghttp3 source exists
if [ ! -d "$NGHTTP3_SOURCE_DIR" ]; then
    echo "Error: nghttp3 source directory not found: $NGHTTP3_SOURCE_DIR"
    echo "Please set NGHTTP3_SOURCE_DIR environment variable or clone nghttp3:"
    echo "  git clone --recurse-submodules https://github.com/ngtcp2/nghttp3.git $NGHTTP3_SOURCE_DIR"
    exit 1
fi

# Ensure required sources are present (sfparse: top-level or lib/sfparse)
if [ ! -f "$NGHTTP3_SOURCE_DIR/sfparse/sfparse.c" ] && [ ! -f "$NGHTTP3_SOURCE_DIR/lib/sfparse/sfparse.c" ]; then
    if [ -d "$NGHTTP3_SOURCE_DIR/.git" ]; then
        echo "Initializing nghttp3 submodules..."
        (cd "$NGHTTP3_SOURCE_DIR" && git submodule update --init --recursive) || {
            echo "Error: Failed to initialize nghttp3 submodules"
            exit 1
        }
    else
        echo "Error: nghttp3 submodules are missing (sfparse)"
        echo "Please clone with submodules:"
        echo "  git clone --recurse-submodules https://github.com/ngtcp2/nghttp3.git $NGHTTP3_SOURCE_DIR"
        echo "Or if already cloned:"
        echo "  cd $NGHTTP3_SOURCE_DIR && git submodule update --init --recursive"
        exit 1
    fi
fi

# Create build directory
BUILD_DIR="build/nghttp3-ios-$ARCH"
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
    -DCMAKE_SYSTEM_NAME=iOS
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET"
    -DCMAKE_OSX_ARCHITECTURES="$ARCH"
    -DCMAKE_OSX_SYSROOT="$IOS_SDK_PATH"
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
    -DENABLE_LIB_ONLY=ON
    -DCMAKE_INSTALL_PREFIX="$(pwd)/install"
)

echo ""
echo "Configuring CMake..."
cmake "$NGHTTP3_SOURCE_DIR" "${CMAKE_ARGS[@]}"

echo ""
echo "Building nghttp3..."
cmake --build . --config "$BUILD_TYPE" -j$(sysctl -n hw.ncpu)

echo ""
echo "Installing..."
cmake --install .

echo ""
echo "Syncing artifacts to ios/libs and ios/include..."
LIBS_DIR="$SCRIPT_DIR/libs"
INCLUDE_DIR="$SCRIPT_DIR/include"
mkdir -p "$LIBS_DIR" "$INCLUDE_DIR"
cp "$(pwd)/install/lib/libnghttp3.a" "$LIBS_DIR/"
if [ -d "$(pwd)/install/include/nghttp3" ]; then
    cp -R "$(pwd)/install/include/nghttp3" "$INCLUDE_DIR/"
fi

echo ""
echo "Build complete!"
echo "Static library: $(pwd)/install/lib/libnghttp3.a"
echo "Headers: $(pwd)/install/include"
