#!/bin/bash
#
# Creates MqttQuicLibs.xcframework from ios/libs/*.a for Swift Package Manager.
# Run after build-openssl.sh, build-ngtcp2.sh, and build-nghttp3.sh have produced
# ios/libs/ (and ios/include/).
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

REQUIRED_LIBS=(
    "libngtcp2.a"
    "libngtcp2_crypto_quictls.a"
    "libnghttp3.a"
    "libssl.a"
    "libcrypto.a"
)

missing=()
for lib in "${REQUIRED_LIBS[@]}"; do
    if [ ! -f "$LIBS_DIR/$lib" ]; then
        missing+=("$lib")
    fi
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "Error: Missing static libraries in $LIBS_DIR:"
    printf '  %s\n' "${missing[@]}"
    echo "Run from plugin root:"
    echo "  cd ios && ./build-openssl.sh && ./build-ngtcp2.sh && ./build-nghttp3.sh"
    echo "Then run this script again."
    exit 1
fi

echo "Merging static libraries..."
mkdir -p "$OUT_DIR"
MERGED="$OUT_DIR/libmqttquic_native.a"
# Remove previous merged lib so libtool doesn't append to it
rm -f "$MERGED"
libtool -static -o "$MERGED" \
    "$LIBS_DIR/libngtcp2.a" \
    "$LIBS_DIR/libngtcp2_crypto_quictls.a" \
    "$LIBS_DIR/libnghttp3.a" \
    "$LIBS_DIR/libssl.a" \
    "$LIBS_DIR/libcrypto.a"

echo "Creating xcframework..."
rm -rf "$XCFRAMEWORK"
xcodebuild -create-xcframework \
    -library "$MERGED" \
    -output "$XCFRAMEWORK"
rm -f "$MERGED"

echo "Done: $XCFRAMEWORK"
