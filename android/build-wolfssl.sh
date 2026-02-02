#!/bin/bash
#
# Build script for WolfSSL on Android (TLS 1.3 + QUIC).
# Used as TLS backend for ngtcp2/nghttp3. Same configurable QUIC support as server (mqttd).
#
# Requires: Android NDK r25+, autoconf, automake, libtool
#
# Usage:
#   ./build-wolfssl.sh [--ndk-path PATH] [--abi ABI] [--platform PLATFORM] [--source DIR]
#
# Example:
#   ./build-wolfssl.sh --ndk-path ~/Android/Sdk/ndk/25.2.9519653 --abi arm64-v8a --platform android-21
#
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
DEPS_DIR="${PROJECT_DIR}/deps"
[ -f "$PROJECT_DIR/deps-versions.sh" ] && . "$PROJECT_DIR/deps-versions.sh"

WOLFSSL_SOURCE_DIR="${WOLFSSL_SOURCE_DIR:-$DEPS_DIR/wolfssl}"
ANDROID_NDK="${ANDROID_NDK:-}"
ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-21}"
INSTALL_PREFIX="${INSTALL_PREFIX:-$SCRIPT_DIR/install/wolfssl-android}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --ndk-path) ANDROID_NDK="$2"; shift 2 ;;
        --abi) ANDROID_ABI="$2"; shift 2 ;;
        --platform) ANDROID_PLATFORM="$2"; shift 2 ;;
        --source) WOLFSSL_SOURCE_DIR="$2"; shift 2 ;;
        --prefix) INSTALL_PREFIX="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Find NDK
if [ -z "$ANDROID_NDK" ]; then
    for d in "$HOME/Android/Sdk/ndk" "$HOME/Library/Android/sdk/ndk"; do
        [ -d "$d" ] && ANDROID_NDK=$(ls -d "$d"/*/ 2>/dev/null | sort -V | tail -1) && break
    done
fi
[ -z "$ANDROID_NDK" ] || [ ! -d "$ANDROID_NDK" ] && { echo "Error: Android NDK not found. Set ANDROID_NDK or use --ndk-path"; exit 1; }

# Prefer ref-code/wolfssl-* if deps/wolfssl missing
if [ ! -d "$WOLFSSL_SOURCE_DIR" ] && [ -d "$PROJECT_DIR/../wolfssl-5.8.4-stable" ]; then
    WOLFSSL_SOURCE_DIR="$PROJECT_DIR/../wolfssl-5.8.4-stable"
fi
if [ ! -d "$WOLFSSL_SOURCE_DIR" ]; then
    echo "Error: WolfSSL source not found at $WOLFSSL_SOURCE_DIR"
    exit 1
fi

# Map ABI to toolchain
case "$ANDROID_ABI" in
    arm64-v8a)   TOOLCHAIN_ARCH=aarch64-linux-android;   API_ARCH=arm64-v8a ;;
    armeabi-v7a) TOOLCHAIN_ARCH=armv7a-linux-androideabi; API_ARCH=armeabi-v7a ;;
    x86_64)      TOOLCHAIN_ARCH=x86_64-linux-android;    API_ARCH=x86_64 ;;
    x86)         TOOLCHAIN_ARCH=i686-linux-android;      API_ARCH=x86 ;;
    *) echo "Error: Unsupported ABI $ANDROID_ABI"; exit 1 ;;
esac
API_LEVEL="${ANDROID_PLATFORM#android-}"
TOOLCHAIN="$ANDROID_NDK/toolchains/llvm/prebuilt/$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"
export PATH="$TOOLCHAIN/bin:$PATH"
CC="$TOOLCHAIN/bin/${TOOLCHAIN_ARCH}${API_LEVEL}-clang"
[ ! -x "$CC" ] && CC="$TOOLCHAIN/bin/${TOOLCHAIN_ARCH}-linux-android${API_LEVEL}-clang"
[ ! -x "$CC" ] && { echo "Error: Clang not found for $ANDROID_ABI"; exit 1; }

INSTALL_PREFIX="$INSTALL_PREFIX/$API_ARCH"
mkdir -p "$INSTALL_PREFIX"

echo "Building WolfSSL (TLS 1.3 + QUIC) for Android"
echo "  Source: $WOLFSSL_SOURCE_DIR"
echo "  ABI: $ANDROID_ABI, Platform: $ANDROID_PLATFORM"
echo "  Install: $INSTALL_PREFIX"

cd "$WOLFSSL_SOURCE_DIR"
# Generate configure if missing (GitHub tarballs don't include it; needs automake)
if [ ! -f ./configure ]; then
    if [ ! -f ./autogen.sh ]; then
        echo "Error: configure and autogen.sh not found in $WOLFSSL_SOURCE_DIR"
        exit 1
    fi
    if ! command -v aclocal &>/dev/null; then
        echo "Error: configure is missing and aclocal (automake) is not installed."
        echo "Install automake, then run autogen.sh in the WolfSSL source:"
        echo "  brew install automake   # macOS"
        echo "  cd $WOLFSSL_SOURCE_DIR"
        echo "  ./autogen.sh"
        echo "Then re-run this build script."
        exit 1
    fi
    # macOS Homebrew: aclocal needs libtool m4 in path (LT_INIT)
    if command -v brew &>/dev/null; then
        BREW_LIBTOOL="$(brew --prefix libtool 2>/dev/null)"
        [ -n "$BREW_LIBTOOL" ] && [ -d "$BREW_LIBTOOL/share/aclocal" ] && \
            export ACLOCAL_PATH="$BREW_LIBTOOL/share/aclocal${ACLOCAL_PATH:+:$ACLOCAL_PATH}"
    fi
    ./autogen.sh
fi
[ ! -f ./configure ] && { echo "Error: configure not found"; exit 1; }

ENABLE_QUIC="${ENABLE_QUIC:-1}"
WOLFSSL_CONFIGURE_QUIC=""
[ "$ENABLE_QUIC" = "1" ] && WOLFSSL_CONFIGURE_QUIC="--enable-quic"

export CC
export CFLAGS="-fPIC"
export CPPFLAGS="-DANDROID"
export LDFLAGS="-fPIC"

./configure \
    --host="$TOOLCHAIN_ARCH" \
    --prefix="$INSTALL_PREFIX" \
    $WOLFSSL_CONFIGURE_QUIC \
    --enable-tls13 \
    --disable-shared \
    --enable-static \
    --disable-examples \
    --disable-crypttests \
    --enable-opensslall \
    --enable-base64encode

make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
make install

echo "WolfSSL built: $INSTALL_PREFIX/lib/libwolfssl.a"
echo "Use with ngtcp2: ./build-ngtcp2.sh --wolfssl-path $INSTALL_PREFIX"
