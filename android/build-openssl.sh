#!/bin/bash
#
# Build script for OpenSSL on Android
#
# This script builds OpenSSL 3.0+ as a static library for Android.
# It requires:
# - Android NDK r25+
# - Android SDK 21+ (API level 21 = Android 5.0)
#
# Usage:
#   ./build-openssl.sh [--ndk-path PATH] [--abi ABI] [--platform PLATFORM] [--version VERSION]
#
# Example:
#   ./build-openssl.sh --ndk-path ~/Android/Sdk/ndk/25.2.9519653 --abi arm64-v8a --platform android-21
#

set -e

# Default values
OPENSSL_VERSION="${OPENSSL_VERSION:-3.2.0}"
ANDROID_NDK="${ANDROID_NDK:-}"
ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-21}"
INSTALL_PREFIX="${INSTALL_PREFIX:-$(pwd)/install/openssl-android}"

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
        --version)
            OPENSSL_VERSION="$2"
            shift 2
            ;;
        --prefix)
            INSTALL_PREFIX="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--ndk-path PATH] [--abi ABI] [--platform PLATFORM]"
            exit 1
            ;;
    esac
done

# Find Android NDK
if [ -z "$ANDROID_NDK" ]; then
    # Try common locations
    if [ -d "$HOME/Android/Sdk/ndk" ]; then
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

echo "Building OpenSSL $OPENSSL_VERSION for Android"
echo "  NDK Path: $ANDROID_NDK"
echo "  ABI: $ANDROID_ABI"
echo "  Platform: $ANDROID_PLATFORM"
echo "  Install Prefix: $INSTALL_PREFIX"

# Check if OpenSSL source exists
OPENSSL_SOURCE_DIR="${OPENSSL_SOURCE_DIR:-../../openssl}"
if [ ! -d "$OPENSSL_SOURCE_DIR" ]; then
    echo "OpenSSL source not found. Cloning..."
    git clone --depth 1 --branch "openssl-$OPENSSL_VERSION" \
        https://github.com/openssl/openssl.git "$OPENSSL_SOURCE_DIR" || \
    git clone --depth 1 https://github.com/openssl/openssl.git "$OPENSSL_SOURCE_DIR"
fi

cd "$OPENSSL_SOURCE_DIR"

# Set up environment for Android cross-compilation
export ANDROID_NDK_ROOT="$ANDROID_NDK"
export PATH="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"

# Determine platform name based on ABI
case "$ANDROID_ABI" in
    arm64-v8a)
        PLATFORM="android-arm64"
        ;;
    armeabi-v7a)
        PLATFORM="android-arm"
        ;;
    x86_64)
        PLATFORM="android-x86_64"
        ;;
    x86)
        PLATFORM="android-x86"
        ;;
    *)
        echo "Error: Unsupported ABI: $ANDROID_ABI"
        exit 1
        ;;
esac

# Configure OpenSSL
echo ""
echo "Configuring OpenSSL for $PLATFORM..."
./Configure "$PLATFORM" \
    --prefix="$INSTALL_PREFIX" \
    --openssldir="$INSTALL_PREFIX/ssl" \
    no-shared \
    no-tests \
    -D__ANDROID_API__=$(echo "$ANDROID_PLATFORM" | sed 's/android-//')

# Build
echo ""
echo "Building OpenSSL..."
make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu)

# Install
echo ""
echo "Installing OpenSSL..."
make install_sw

echo ""
echo "OpenSSL build complete!"
echo "Installation directory: $INSTALL_PREFIX"
echo "Libraries: $INSTALL_PREFIX/lib"
echo "Headers: $INSTALL_PREFIX/include"
