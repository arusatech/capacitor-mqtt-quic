#!/bin/bash
#
# Creates MqttQuicLibs.xcframework from ios/libs/*.a (device) and optionally libs-simulator/*.a (simulator).
# For device + simulator (required for "Run on iPhone Simulator"), run build-native.sh first (builds both).
# Default build uses WolfSSL; run build-native.sh from plugin root, then this script.
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
LIBS_SIM_DIR="$IOS_DIR/libs-simulator"
LIBS_SIM_X86_DIR="$IOS_DIR/libs-simulator-x86_64"
OUT_DIR="$IOS_DIR/libs"
XCFRAMEWORK="$OUT_DIR/MqttQuicLibs.xcframework"

# Require device libs (ngtcp2 + nghttp3)
if [ ! -f "$LIBS_DIR/libngtcp2.a" ] || [ ! -f "$LIBS_DIR/libnghttp3.a" ]; then
    echo "Error: Missing libngtcp2.a or libnghttp3.a in $LIBS_DIR"
    echo "From plugin root run: ./build-native.sh"
    echo "Then run this script again."
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

mkdir -p "$OUT_DIR"

# Merge device libs
echo "Merging device static libraries (TLS: $([ "$USE_WOLFSSL" = "1" ] && echo WolfSSL || echo QuicTLS))..."
MERGED_DEVICE="$OUT_DIR/libmqttquic_native_device.a"
rm -f "$MERGED_DEVICE"
if [ "$USE_WOLFSSL" = "1" ]; then
    libtool -static -o "$MERGED_DEVICE" \
        "$LIBS_DIR/libngtcp2.a" \
        "$LIBS_DIR/libngtcp2_crypto_wolfssl.a" \
        "$LIBS_DIR/libnghttp3.a" \
        "$LIBS_DIR/libwolfssl.a"
else
    libtool -static -o "$MERGED_DEVICE" \
        "$LIBS_DIR/libngtcp2.a" \
        "$LIBS_DIR/libngtcp2_crypto_quictls.a" \
        "$LIBS_DIR/libnghttp3.a" \
        "$LIBS_DIR/libssl.a" \
        "$LIBS_DIR/libcrypto.a"
fi

# Simulator slice (optional; required for running on iOS Simulator)
HAVE_SIMULATOR=0
if [ -f "$LIBS_SIM_DIR/libngtcp2.a" ] && [ -f "$LIBS_SIM_DIR/libnghttp3.a" ]; then
    if [ "$USE_WOLFSSL" = "1" ] && [ -f "$LIBS_SIM_DIR/libngtcp2_crypto_wolfssl.a" ] && [ -f "$LIBS_SIM_DIR/libwolfssl.a" ]; then
        HAVE_SIMULATOR=1
    elif [ "$USE_WOLFSSL" = "0" ] && [ -f "$LIBS_SIM_DIR/libngtcp2_crypto_quictls.a" ] && [ -f "$LIBS_SIM_DIR/libssl.a" ]; then
        HAVE_SIMULATOR=1
    fi
fi

if [ "$HAVE_SIMULATOR" = "1" ]; then
    echo "Merging simulator static libraries (arm64)..."
    MERGED_SIM_ARM64="$OUT_DIR/libmqttquic_native_simulator_arm64.a"
    rm -f "$MERGED_SIM_ARM64"
    if [ "$USE_WOLFSSL" = "1" ]; then
        libtool -static -o "$MERGED_SIM_ARM64" \
            "$LIBS_SIM_DIR/libngtcp2.a" \
            "$LIBS_SIM_DIR/libngtcp2_crypto_wolfssl.a" \
            "$LIBS_SIM_DIR/libnghttp3.a" \
            "$LIBS_SIM_DIR/libwolfssl.a"
    else
        libtool -static -o "$MERGED_SIM_ARM64" \
            "$LIBS_SIM_DIR/libngtcp2.a" \
            "$LIBS_SIM_DIR/libngtcp2_crypto_quictls.a" \
            "$LIBS_SIM_DIR/libnghttp3.a" \
            "$LIBS_SIM_DIR/libssl.a" \
            "$LIBS_SIM_DIR/libcrypto.a"
    fi

    MERGED_SIM="$MERGED_SIM_ARM64"
    # If x86_64 simulator libs exist, create a fat simulator library
    if [ -f "$LIBS_SIM_X86_DIR/libngtcp2.a" ] && [ -f "$LIBS_SIM_X86_DIR/libnghttp3.a" ]; then
        echo "Merging simulator static libraries (x86_64) and creating fat simulator slice..."
        MERGED_SIM_X86="$OUT_DIR/libmqttquic_native_simulator_x86_64.a"
        rm -f "$MERGED_SIM_X86"
        if [ "$USE_WOLFSSL" = "1" ]; then
            libtool -static -o "$MERGED_SIM_X86" \
                "$LIBS_SIM_X86_DIR/libngtcp2.a" \
                "$LIBS_SIM_X86_DIR/libngtcp2_crypto_wolfssl.a" \
                "$LIBS_SIM_X86_DIR/libnghttp3.a" \
                "$LIBS_SIM_X86_DIR/libwolfssl.a"
        else
            libtool -static -o "$MERGED_SIM_X86" \
                "$LIBS_SIM_X86_DIR/libngtcp2.a" \
                "$LIBS_SIM_X86_DIR/libngtcp2_crypto_quictls.a" \
                "$LIBS_SIM_X86_DIR/libnghttp3.a" \
                "$LIBS_SIM_X86_DIR/libssl.a" \
                "$LIBS_SIM_X86_DIR/libcrypto.a"
        fi
        MERGED_SIM="$OUT_DIR/libmqttquic_native_simulator.a"
        rm -f "$MERGED_SIM"
        lipo -create "$MERGED_SIM_ARM64" "$MERGED_SIM_X86" -output "$MERGED_SIM"
    fi
fi

echo "Creating xcframework..."
rm -rf "$XCFRAMEWORK"
if [ "$HAVE_SIMULATOR" = "1" ]; then
    xcodebuild -create-xcframework \
        -library "$MERGED_DEVICE" \
        -library "$MERGED_SIM" \
        -output "$XCFRAMEWORK"
    rm -f "$MERGED_DEVICE" "$MERGED_SIM" "$MERGED_SIM_ARM64" "$MERGED_SIM_X86"
else
    xcodebuild -create-xcframework \
        -library "$MERGED_DEVICE" \
        -output "$XCFRAMEWORK"
    rm -f "$MERGED_DEVICE"
    echo "Warning: No simulator slice (libs-simulator/ missing or incomplete). Run ./build-native.sh from plugin root to build device+simulator, then re-run this script."
fi

echo "Done: $XCFRAMEWORK"
