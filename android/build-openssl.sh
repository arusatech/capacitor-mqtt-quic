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
#   ./build-openssl.sh [--ndk-path PATH] [--abi ABI] [--platform PLATFORM] [--version VERSION] [--quictls] [--quictls-branch BRANCH]
#
# Example:
#   ./build-openssl.sh --ndk-path ~/Android/Sdk/ndk/25.2.9519653 --abi arm64-v8a --platform android-21 --quictls
#

set -e

# Default values
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -n "$PROJECT_DIR" ]; then
    REF_CODE_DIR="$(cd "$PROJECT_DIR/ref-code" && pwd)"
else
    REF_CODE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi
DEFAULT_OPENSSL_SOURCE_DIR=""
if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR/ref-code/openssl" ]; then
    DEFAULT_OPENSSL_SOURCE_DIR="$(cd "$PROJECT_DIR/ref-code/openssl" && pwd)"
elif [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR/ref-code.openssl" ]; then
    DEFAULT_OPENSSL_SOURCE_DIR="$(cd "$PROJECT_DIR/ref-code.openssl" && pwd)"
elif [ -d "$SCRIPT_DIR/../ref-code/openssl" ]; then
    DEFAULT_OPENSSL_SOURCE_DIR="$(cd "$SCRIPT_DIR/../ref-code/openssl" && pwd)"
elif [ -d "$SCRIPT_DIR/../ref-code.openssl" ]; then
    DEFAULT_OPENSSL_SOURCE_DIR="$(cd "$SCRIPT_DIR/../ref-code.openssl" && pwd)"
else
    DEFAULT_OPENSSL_SOURCE_DIR="$REF_CODE_DIR/openssl"
fi
OPENSSL_VERSION="${OPENSSL_VERSION:-3.2.0}"
USE_QUICTLS="${USE_QUICTLS:-0}"
QUICTLS_BRANCH="${QUICTLS_BRANCH:-openssl-3.1.7+quic}"
ANDROID_NDK="${ANDROID_NDK:-}"
ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-21}"
INSTALL_PREFIX="${INSTALL_PREFIX:-$SCRIPT_DIR/install/openssl-android}"

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
        --quictls)
            USE_QUICTLS=1
            shift
            ;;
        --quictls-branch)
            QUICTLS_BRANCH="$2"
            USE_QUICTLS=1
            shift 2
            ;;
        --prefix)
            INSTALL_PREFIX="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--ndk-path PATH] [--abi ABI] [--platform PLATFORM] [--version VERSION] [--quictls] [--quictls-branch BRANCH]"
            exit 1
            ;;
    esac
done

# Find Android NDK
if [ -z "$ANDROID_NDK" ]; then
    # Try common locations (macOS + Linux)
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

if [ "$USE_QUICTLS" = "1" ]; then
    echo "Building quictls ($QUICTLS_BRANCH) for Android"
else
    echo "Building OpenSSL $OPENSSL_VERSION for Android"
fi
echo "  NDK Path: $ANDROID_NDK"
echo "  ABI: $ANDROID_ABI"
echo "  Platform: $ANDROID_PLATFORM"
# Make install prefix ABI-aware by default
if [[ "$INSTALL_PREFIX" != *"/$ANDROID_ABI" ]]; then
    INSTALL_PREFIX="$INSTALL_PREFIX/$ANDROID_ABI"
fi

echo "  Install Prefix: $INSTALL_PREFIX"

# Make install prefix ABI-aware by default
if [[ "$INSTALL_PREFIX" != *"/$ANDROID_ABI" ]]; then
    INSTALL_PREFIX="$INSTALL_PREFIX/$ANDROID_ABI"
fi

# Check if OpenSSL/quictls source exists
if [ "$USE_QUICTLS" = "1" ]; then
    OPENSSL_SOURCE_DIR="${OPENSSL_SOURCE_DIR:-$DEFAULT_OPENSSL_SOURCE_DIR}"
    OPENSSL_REPO_URL="https://github.com/quictls/openssl.git"
    OPENSSL_REPO_BRANCH="$QUICTLS_BRANCH"
else
    OPENSSL_SOURCE_DIR="${OPENSSL_SOURCE_DIR:-$DEFAULT_OPENSSL_SOURCE_DIR}"
    OPENSSL_REPO_URL="https://github.com/openssl/openssl.git"
    OPENSSL_REPO_BRANCH="openssl-$OPENSSL_VERSION"
fi
if [ ! -d "$OPENSSL_SOURCE_DIR" ]; then
    echo "OpenSSL source not found. Cloning..."
    git clone --depth 1 --branch "$OPENSSL_REPO_BRANCH" \
        "$OPENSSL_REPO_URL" "$OPENSSL_SOURCE_DIR" || \
    git clone --depth 1 "$OPENSSL_REPO_URL" "$OPENSSL_SOURCE_DIR"
fi

# Validate quictls source when requested
if [ "$USE_QUICTLS" = "1" ]; then
    if ! grep -q "SSL_provide_quic_data" "$OPENSSL_SOURCE_DIR/include/openssl/ssl.h.in" 2>/dev/null; then
        echo "Error: OPENSSL_SOURCE_DIR does not appear to be quictls."
        echo "Please clone quictls into $OPENSSL_SOURCE_DIR or set OPENSSL_SOURCE_DIR to a quictls checkout."
        echo "Example:"
        echo "  git clone --depth 1 --branch $QUICTLS_BRANCH $OPENSSL_REPO_URL $OPENSSL_SOURCE_DIR"
        exit 1
    fi
fi

cd "$OPENSSL_SOURCE_DIR"

# Set up environment for Android cross-compilation
export ANDROID_NDK_ROOT="$ANDROID_NDK"
export ANDROID_NDK_HOME="$ANDROID_NDK"
# Pick correct host toolchain for macOS/Linux
HOST_TAG=""
UNAME_S="$(uname -s)"
UNAME_M="$(uname -m)"
HOST_TAG_CANDIDATES=()
if [ "$UNAME_S" = "Darwin" ]; then
    if [ "$UNAME_M" = "arm64" ]; then
        HOST_TAG_CANDIDATES=("darwin-arm64" "darwin-x86_64")
    else
        HOST_TAG_CANDIDATES=("darwin-x86_64" "darwin-arm64")
    fi
else
    HOST_TAG_CANDIDATES=("linux-x86_64")
fi

for tag in "${HOST_TAG_CANDIDATES[@]}"; do
    if [ -d "$ANDROID_NDK/toolchains/llvm/prebuilt/$tag" ]; then
        HOST_TAG="$tag"
        break
    fi
done

if [ -z "$HOST_TAG" ]; then
    echo "Error: Could not find an NDK prebuilt toolchain for this host"
    echo "Checked: ${HOST_TAG_CANDIDATES[*]}"
    exit 1
fi

export PATH="$ANDROID_NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin:$PATH"

# Determine platform name based on ABI
case "$ANDROID_ABI" in
    arm64-v8a)
        PLATFORM="android-arm64"
        TOOLCHAIN_PREFIX="aarch64-linux-android"
        ;;
    armeabi-v7a)
        PLATFORM="android-arm"
        TOOLCHAIN_PREFIX="armv7a-linux-androideabi"
        ;;
    x86_64)
        PLATFORM="android-x86_64"
        TOOLCHAIN_PREFIX="x86_64-linux-android"
        ;;
    x86)
        PLATFORM="android-x86"
        TOOLCHAIN_PREFIX="i686-linux-android"
        ;;
    *)
        echo "Error: Unsupported ABI: $ANDROID_ABI"
        exit 1
        ;;
esac

ANDROID_API=$(echo "$ANDROID_PLATFORM" | sed 's/android-//')
export ANDROID_API

# Use clang toolchain from NDK (gcc was removed in r23+)
export CC="${TOOLCHAIN_PREFIX}${ANDROID_API}-clang"
export CXX="${TOOLCHAIN_PREFIX}${ANDROID_API}-clang++"
export AR="llvm-ar"
export RANLIB="llvm-ranlib"
export LD="ld.lld"
export STRIP="llvm-strip"

# Clean previous build if it exists (important for QUIC support)
echo ""
echo "Cleaning previous OpenSSL build (if any)..."
if [ -f "Makefile" ] || [ -f "configdata.pm" ]; then
    make distclean 2>/dev/null || true
    rm -f configdata.pm Makefile 2>/dev/null || true
fi

# Configure OpenSSL
echo ""
echo "Configuring OpenSSL for $PLATFORM..."
QUIC_OPTION="enable-quic"

# quictls older branches may not support "no-apps"
NO_APPS_OPTION=""
if ./Configure list 2>/dev/null | grep -q "no-apps"; then
    NO_APPS_OPTION="no-apps"
fi

./Configure "$PLATFORM" \
    --prefix="$INSTALL_PREFIX" \
    --openssldir="$INSTALL_PREFIX/ssl" \
    no-shared \
    no-tests \
    $NO_APPS_OPTION \
    "$QUIC_OPTION" \
    -D__ANDROID_API__="$ANDROID_API"

# Build
echo ""
echo "Building OpenSSL..."
# Build everything, but allow failures in apps/providers
make -k -j$(nproc 2>/dev/null || sysctl -n hw.ncpu) || true

# Verify that the required libraries were built
if [ ! -f "libcrypto.a" ] || [ ! -f "libssl.a" ]; then
    echo "Error: Required libraries were not built"
    echo "Attempting to build libraries directly..."
    make libcrypto.a libssl.a -j$(nproc 2>/dev/null || sysctl -n hw.ncpu) || {
        echo "Error: Failed to build libcrypto.a and libssl.a"
        exit 1
    }
fi

# Install
echo ""
echo "Installing OpenSSL..."
make -k install_sw || {
    echo "Warning: install_sw had some errors, but checking if libraries were installed..."
    if [ -f "libcrypto.a" ] && [ -f "libssl.a" ]; then
        echo "Copying libraries manually..."
        mkdir -p "$INSTALL_PREFIX/lib"
        cp libcrypto.a libssl.a "$INSTALL_PREFIX/lib/" 2>/dev/null || true
        echo "Copying headers manually..."
        mkdir -p "$INSTALL_PREFIX/include"
        cp -r include/openssl "$INSTALL_PREFIX/include/" 2>/dev/null || true
    fi
}

if [ "$USE_QUICTLS" = "1" ]; then
    if ! grep -q "SSL_provide_quic_data" "$INSTALL_PREFIX/include/openssl/ssl.h" 2>/dev/null; then
        echo "Error: Installed OpenSSL headers do not include QUIC APIs."
        echo "Ensure OPENSSL_SOURCE_DIR points to a quictls checkout."
        exit 1
    fi
fi

echo ""
echo "OpenSSL build complete!"
echo "Installation directory: $INSTALL_PREFIX"
echo "Libraries: $INSTALL_PREFIX/lib"
echo "Headers: $INSTALL_PREFIX/include"
