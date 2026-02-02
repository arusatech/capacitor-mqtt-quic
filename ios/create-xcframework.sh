#!/bin/bash
#
# Creates MqttQuicLibs.xcframework from ios/libs/*.a for Swift Package Manager.
# Default build uses WolfSSL (TLS 1.3 + QUIC); run build-native.sh or build-wolfssl then nghttp3 then ngtcp2.
# Optional: QuicTLS via build-openssl.sh then ngtcp2 --quictls.
#
# Usage: from plugin root or from ios/
#   ./create-xcframework.sh
#
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/../package.json" ]; then
    IOS_DIR="$SCRIPT_DIR"
else
    IOS_DIR="$(pwd)"
fi
LIBS_DIR="$IOS_DIR/libs"
OUT_DIR="$IOS_DIR/Libs"
XCFRAMEWORK="$OUT_DIR/MqttQuicLibs.xcframework"

# Require ngtcp2 + nghttp3; TLS = WolfSSL or QuicTLS
if [ ! -f "$LIBS_DIR/libngtcp2.a" ] || [ ! -f "$LIBS_DIR/libnghttp3.a" ]; then
    echo "Error: Missing libngtcp2.a or libnghttp3.a in $LIBS_DIR"
    echo "Default (WolfSSL): from plugin root run ./build-native.sh (builds WolfSSL by default)"
    echo "Or: cd ios && ./build-wolfssl.sh && ./build-nghttp3.sh && ./build-ngtcp2.sh --wolfssl-path ./install/wolfssl-ios"
    echo "QuicTLS: cd ios && ./build-openssl.sh && ./build-nghttp3.sh && ./build-ngtcp2.sh --quictls"
    exit 1
fi
USE_WOLFSSL=0
[ -f "$LIBS_DIR/libngtcp2_crypto_wolfssl.a" ] && [ -f "$LIBS_DIR/libwolfssl.a" ] && USE_WOLFSSL=1
if [ "$USE_WOLFSSL" = "0" ]; then
    for lib in libngtcp2_crypto_quictls.a libssl.a libcrypto.a; do
        if [ ! -f "$LIBS_DIR/$lib" ]; then
            echo "Error: Missing $lib (QuicTLS build). By default use WolfSSL: run ./build-native.sh from plugin root."
            exit 1
        fi
    done
fi

echo "Merging static libraries (TLS: $([ "$USE_WOLFSSL" = "1" ] && echo WolfSSL || echo QuicTLS))..."
mkdir -p "$OUT_DIR"
MERGED="$OUT_DIR/libmqttquic_native.a"
rm -f "$MERGED"
if [ "$USE_WOLFSSL" = "1" ]; then
    libtool -static -o "$MERGED" \
        "$LIBS_DIR/libngtcp2.a" \
        "$LIBS_DIR/libngtcp2_crypto_wolfssl.a" \
        "$LIBS_DIR/libnghttp3.a" \
        "$LIBS_DIR/libwolfssl.a"
else
    libtool -static -o "$MERGED" \
        "$LIBS_DIR/libngtcp2.a" \
        "$LIBS_DIR/libngtcp2_crypto_quictls.a" \
        "$LIBS_DIR/libnghttp3.a" \
        "$LIBS_DIR/libssl.a" \
        "$LIBS_DIR/libcrypto.a"
fi

echo "Creating xcframework..."
rm -rf "$XCFRAMEWORK"
xcodebuild -create-xcframework \
    -library "$MERGED" \
    -output "$XCFRAMEWORK"
rm -f "$MERGED"

echo "Done: $XCFRAMEWORK"
