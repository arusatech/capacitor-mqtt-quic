#!/bin/bash
#
# Build script for WolfSSL on iOS (TLS 1.3 + QUIC).
# Used as TLS backend for ngtcp2/nghttp3. Same configurable QUIC support as server (mqttd).
#
# Requires: Xcode 14+, autoconf, automake, libtool
#
# Usage:
#   ./build-wolfssl.sh [--arch ARCH] [--sdk SDK] [--source DIR]
#
# Example:
#   ./build-wolfssl.sh --arch arm64 --sdk iphoneos
#
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
DEPS_DIR="${PROJECT_DIR}/deps"
[ -f "$PROJECT_DIR/deps-versions.sh" ] && . "$PROJECT_DIR/deps-versions.sh"

WOLFSSL_SOURCE_DIR="${WOLFSSL_SOURCE_DIR:-$DEPS_DIR/wolfssl}"
ARCH="${ARCH:-arm64}"
SDK="${SDK:-iphoneos}"
IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-15.0}"
if [ "$SDK" = "iphonesimulator" ]; then
    INSTALL_PREFIX="${INSTALL_PREFIX:-$SCRIPT_DIR/install/wolfssl-ios-simulator}"
    LIBS_DIR="${LIBS_DIR:-$SCRIPT_DIR/libs-simulator}"
else
    INSTALL_PREFIX="${INSTALL_PREFIX:-$SCRIPT_DIR/install/wolfssl-ios}"
    LIBS_DIR="${LIBS_DIR:-$SCRIPT_DIR/libs}"
fi
INCLUDE_DIR="${SCRIPT_DIR}/include"

while [[ $# -gt 0 ]]; do
    case $1 in
        --arch) ARCH="$2"; shift 2 ;;
        --sdk) SDK="$2"; shift 2 ;;
        --source) WOLFSSL_SOURCE_DIR="$2"; shift 2 ;;
        --prefix) INSTALL_PREFIX="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if ! command -v xcrun &> /dev/null; then
    echo "Error: Xcode command line tools required"
    exit 1
fi
IOS_SDK_PATH=$(xcrun --sdk "$SDK" --show-sdk-path)
[ -z "$IOS_SDK_PATH" ] && { echo "Error: SDK $SDK not found"; exit 1; }

# Prefer ref-code/wolfssl-* if deps/wolfssl missing
if [ ! -d "$WOLFSSL_SOURCE_DIR" ] && [ -d "$PROJECT_DIR/../wolfssl-5.8.4-stable" ]; then
    WOLFSSL_SOURCE_DIR="$PROJECT_DIR/../wolfssl-5.8.4-stable"
fi
if [ ! -d "$WOLFSSL_SOURCE_DIR" ]; then
    echo "Error: WolfSSL source not found at $WOLFSSL_SOURCE_DIR"
    echo "Clone: git clone --depth 1 -b ${WOLFSSL_TAG:-v5.8.4-stable} ${WOLFSSL_REPO_URL:-https://github.com/wolfSSL/wolfssl.git} $DEPS_DIR/wolfssl"
    exit 1
fi

echo "Building WolfSSL (TLS 1.3 + QUIC) for iOS"
echo "  Source: $WOLFSSL_SOURCE_DIR"
echo "  Arch: $ARCH, SDK: $SDK"
echo "  Install: $INSTALL_PREFIX"

[ -f "$PROJECT_DIR/deps-versions.sh" ] && . "$PROJECT_DIR/deps-versions.sh"
ENABLE_QUIC="${ENABLE_QUIC:-1}"

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
        echo "  brew install automake"
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

export CC="$(xcrun --sdk "$SDK" --find clang)"
export CFLAGS="-arch $ARCH -isysroot $IOS_SDK_PATH -mios-version-min=$IOS_DEPLOYMENT_TARGET -fno-common"
export CPPFLAGS="-arch $ARCH -isysroot $IOS_SDK_PATH -mios-version-min=$IOS_DEPLOYMENT_TARGET"
export LDFLAGS="-arch $ARCH -isysroot $IOS_SDK_PATH -mios-version-min=$IOS_DEPLOYMENT_TARGET"

WOLFSSL_CONFIGURE_QUIC=""
[ "$ENABLE_QUIC" = "1" ] && WOLFSSL_CONFIGURE_QUIC="--enable-quic"
./configure \
    --host="${ARCH}-apple-darwin" \
    --prefix="$INSTALL_PREFIX" \
    $WOLFSSL_CONFIGURE_QUIC \
    --enable-tls13 \
    --disable-shared \
    --enable-static \
    --disable-examples \
    --disable-crypttests \
    --enable-opensslall \
    --enable-base64encode

make -j$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)
make install

mkdir -p "$LIBS_DIR" "$INCLUDE_DIR"
cp -f "$INSTALL_PREFIX/lib/libwolfssl.a" "$LIBS_DIR/"
rm -rf "$INCLUDE_DIR/wolfssl"
cp -R "$INSTALL_PREFIX/include/wolfssl" "$INCLUDE_DIR/"

echo "WolfSSL built: $LIBS_DIR/libwolfssl.a, $INCLUDE_DIR/wolfssl/"
echo "Use with ngtcp2: ./build-ngtcp2.sh --wolfssl-path $INSTALL_PREFIX"
