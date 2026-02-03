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

# Default values: PROJECT_DIR = plugin root (where build-native.sh lives)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -z "$PROJECT_DIR" ]; then
    PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
DEPS_DIR="${PROJECT_DIR}/deps"
[ -f "$PROJECT_DIR/deps-versions.sh" ] && . "$PROJECT_DIR/deps-versions.sh"
NGHTTP3_SOURCE_DIR="${NGHTTP3_SOURCE_DIR:-${DEPS_DIR}/nghttp3}"
if [[ "$NGHTTP3_SOURCE_DIR" != /* ]]; then
    NGHTTP3_SOURCE_DIR="${DEPS_DIR}/$NGHTTP3_SOURCE_DIR"
fi
ARCH="${ARCH:-arm64}"
SDK="${SDK:-iphoneos}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-15.0}"
[ "$SDK" = "iphonesimulator" ] && LIBS_DIR="${LIBS_DIR:-$SCRIPT_DIR/libs-simulator}" || LIBS_DIR="${LIBS_DIR:-$SCRIPT_DIR/libs}"

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

# Clone nghttp3 if missing (URL from deps-versions.sh / ref-code/VERSION.txt)
NGHTTP3_REPO_URL="${NGHTTP3_REPO_URL:-https://github.com/ngtcp2/nghttp3.git}"
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
        echo "  git clone --recurse-submodules $NGHTTP3_REPO_URL $NGHTTP3_SOURCE_DIR"
        echo "Or if already cloned:"
        echo "  cd $NGHTTP3_SOURCE_DIR && git submodule update --init --recursive"
        exit 1
    fi
fi

# Create build directory (separate for simulator so device build is not overwritten)
SDK_SUFFIX=""
[ "$SDK" = "iphonesimulator" ] && SDK_SUFFIX="-simulator"
BUILD_DIR="build/nghttp3-ios-${ARCH}${SDK_SUFFIX}"
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
echo "Syncing artifacts to $LIBS_DIR and ios/include..."
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
