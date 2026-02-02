#!/bin/bash
#
# Build script for ngtcp2 on Android
# Builds ngtcp2 as a native library for Android using NDK.
# Default TLS backend: WolfSSL (TLS 1.3 + QUIC). Set USE_WOLFSSL=0 or use --openssl-path for QuicTLS.
# Requires: Android NDK r25+, CMake 3.20+, and WolfSSL or OpenSSL/QuicTLS built for Android.
#
# Usage:
#   ./build-ngtcp2.sh [--wolfssl-path PATH] [--openssl-path PATH] [--ndk-path PATH] [--abi ABI] [--platform PLATFORM]
#
# Example (default WolfSSL): ./build-ngtcp2.sh   # uses install/wolfssl-android when USE_WOLFSSL=1
# Example (QuicTLS): ./build-ngtcp2.sh --openssl-path ./install/openssl-android --quictls
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
WOLFSSL_PATH="${WOLFSSL_PATH:-}"
OPENSSL_PATH="${OPENSSL_PATH:-}"
USE_WOLFSSL="${USE_WOLFSSL:-1}"
USE_QUICTLS="${USE_QUICTLS:-1}"
INSTALL_PREFIX="${INSTALL_PREFIX:-$SCRIPT_DIR/install/ngtcp2-android}"

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
        --wolfssl-path)
            WOLFSSL_PATH="$2"
            USE_WOLFSSL=1
            shift 2
            ;;
        --openssl-path)
            OPENSSL_PATH="$2"
            shift 2
            ;;
        --prefix)
            INSTALL_PREFIX="$2"
            shift 2
            ;;
        --quictls)
            USE_QUICTLS=1
            USE_WOLFSSL=0
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--wolfssl-path PATH] [--openssl-path PATH] [--ndk-path PATH] [--abi ABI] [--platform PLATFORM] [--quictls]"
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
    # Try common locations (macOS + Linux)
    if [ -d "$HOME/Android/Sdk/ndk" ]; then
        # Find latest NDK version
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

echo "Building ngtcp2 for Android"
echo "  NDK Path: $ANDROID_NDK"
echo "  ABI: $ANDROID_ABI"
echo "  Platform: $ANDROID_PLATFORM"
echo "  Build Type: $BUILD_TYPE"
if [[ "$INSTALL_PREFIX" != *"/$ANDROID_ABI" ]]; then
    INSTALL_PREFIX="$INSTALL_PREFIX/$ANDROID_ABI"
fi
echo "  Install Prefix: $INSTALL_PREFIX"

# Resolve ngtcp2 source dir (default: deps/ngtcp2); URL from deps-versions.sh / ref-code/VERSION.txt
NGTCP2_SOURCE_DIR="${NGTCP2_SOURCE_DIR:-${DEPS_DIR}/ngtcp2}"
if [[ "$NGTCP2_SOURCE_DIR" != /* ]]; then
    NGTCP2_SOURCE_DIR="${DEPS_DIR}/$NGTCP2_SOURCE_DIR"
fi
NGTCP2_REPO_URL="${NGTCP2_REPO_URL:-https://github.com/ngtcp2/ngtcp2.git}"
# Clone ngtcp2 if missing
if [ ! -d "$NGTCP2_SOURCE_DIR" ]; then
    echo "ngtcp2 source not found. Cloning into $NGTCP2_SOURCE_DIR ..."
    mkdir -p "$DEPS_DIR"
    git clone --recurse-submodules "$NGTCP2_REPO_URL" "$NGTCP2_SOURCE_DIR" || {
        echo "Error: Failed to clone ngtcp2"
        exit 1
    }
fi
if [ -n "$NGTCP2_COMMIT" ] && [ -d "$NGTCP2_SOURCE_DIR/.git" ]; then
    echo "Pinning ngtcp2 to commit $NGTCP2_COMMIT"
    (cd "$NGTCP2_SOURCE_DIR" && git fetch origin "$NGTCP2_COMMIT" 2>/dev/null; git checkout "$NGTCP2_COMMIT") || {
        echo "Error: Failed to checkout ngtcp2 commit $NGTCP2_COMMIT"
        exit 1
    }
fi

# Ensure required submodules are present (munit)
if [ ! -f "$NGTCP2_SOURCE_DIR/munit/munit.c" ]; then
    if [ -d "$NGTCP2_SOURCE_DIR/.git" ]; then
        echo "Initializing ngtcp2 submodules..."
        (cd "$NGTCP2_SOURCE_DIR" && git submodule update --init --recursive) || {
            echo "Error: Failed to initialize ngtcp2 submodules"
            exit 1
        }
    else
        echo "Warning: ngtcp2 submodules are missing (munit)"
        echo "Tests will be disabled, but if configuration still fails, clone with submodules:"
        echo "  git clone --recurse-submodules $NGTCP2_REPO_URL $NGTCP2_SOURCE_DIR"
    fi
fi

# Prefer WolfSSL when USE_WOLFSSL=1
if [ "$USE_WOLFSSL" = "1" ] && [ -z "$WOLFSSL_PATH" ]; then
    if [ -d "$SCRIPT_DIR/install/wolfssl-android/$ANDROID_ABI" ]; then
        WOLFSSL_PATH="$SCRIPT_DIR/install/wolfssl-android/$ANDROID_ABI"
    elif [ -d "$SCRIPT_DIR/install/wolfssl-android" ]; then
        WOLFSSL_PATH="$SCRIPT_DIR/install/wolfssl-android"
    fi
fi
if [ -z "$WOLFSSL_PATH" ] && [ -z "$OPENSSL_PATH" ]; then
    if [ -d "$SCRIPT_DIR/install/openssl-android/$ANDROID_ABI" ]; then
        OPENSSL_PATH="$SCRIPT_DIR/install/openssl-android/$ANDROID_ABI"
    elif [ -d "$SCRIPT_DIR/install/openssl-android" ]; then
        OPENSSL_PATH="$SCRIPT_DIR/install/openssl-android"
    fi
fi
if [ -z "$WOLFSSL_PATH" ] && [ -z "$OPENSSL_PATH" ]; then
    echo "Warning: No TLS path. Build WolfSSL or OpenSSL first."
    echo "  WolfSSL: ./build-wolfssl.sh  then  ./build-ngtcp2.sh --wolfssl-path ./install/wolfssl-android"
    echo "  QuicTLS: ./build-openssl.sh  then  ./build-ngtcp2.sh --openssl-path ./install/openssl-android --quictls"
fi

# Create build directory
BUILD_DIR="build/android-$ANDROID_ABI"
mkdir -p "$BUILD_DIR"

# Clean build dir if CMake cache points to a different source tree
if [ -f "$BUILD_DIR/CMakeCache.txt" ]; then
    CMAKE_HOME_DIR=$(grep "^CMAKE_HOME_DIRECTORY:INTERNAL=" "$BUILD_DIR/CMakeCache.txt" | cut -d= -f2-)
    if [ -n "$CMAKE_HOME_DIR" ] && [ "$CMAKE_HOME_DIR" != "$NGTCP2_SOURCE_DIR" ]; then
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
    -DENABLE_TESTS=OFF
    -DENABLE_EXAMPLES=OFF
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX"
)

if [ -n "$WOLFSSL_PATH" ]; then
    if [[ "$WOLFSSL_PATH" != /* ]]; then
        [ -d "$SCRIPT_DIR/$WOLFSSL_PATH" ] && WOLFSSL_PATH="$SCRIPT_DIR/$WOLFSSL_PATH"
        [ -d "$DEPS_DIR/$WOLFSSL_PATH" ] && WOLFSSL_PATH="$DEPS_DIR/$WOLFSSL_PATH"
    fi
    [ -d "$WOLFSSL_PATH/$ANDROID_ABI" ] && WOLFSSL_PATH="$WOLFSSL_PATH/$ANDROID_ABI"
    WOLFSSL_PATH="$(cd "$WOLFSSL_PATH" 2>/dev/null && pwd)" || true
    if [ -d "$WOLFSSL_PATH" ] && [ -f "$WOLFSSL_PATH/lib/libwolfssl.a" ]; then
        CMAKE_ARGS+=(
            -DENABLE_WOLFSSL=ON
            -DENABLE_OPENSSL=OFF
            -DWOLFSSL_INCLUDE_DIR="$WOLFSSL_PATH/include"
            -DWOLFSSL_LIBRARY="$WOLFSSL_PATH/lib/libwolfssl.a"
        )
    fi
fi
if [ -z "$WOLFSSL_PATH" ] || [ ! -f "$WOLFSSL_PATH/lib/libwolfssl.a" ]; then
if [ -n "$OPENSSL_PATH" ]; then
    if [[ "$OPENSSL_PATH" != /* ]]; then
        if [ -d "$SCRIPT_DIR/$OPENSSL_PATH" ]; then
            OPENSSL_PATH="$SCRIPT_DIR/$OPENSSL_PATH"
        else
            OPENSSL_PATH="$DEPS_DIR/$OPENSSL_PATH"
        fi
    fi
    [ -d "$OPENSSL_PATH/$ANDROID_ABI" ] && OPENSSL_PATH="$OPENSSL_PATH/$ANDROID_ABI"
    if [ ! -d "$OPENSSL_PATH" ]; then
        echo "Error: OpenSSL path does not exist: $OPENSSL_PATH"
        exit 1
    fi
    OPENSSL_PATH="$(cd "$OPENSSL_PATH" && pwd)"
    OPENSSL_LIB_DIR="$OPENSSL_PATH/lib"
    OPENSSL_INCLUDE_DIR="$OPENSSL_PATH/include"
    OPENSSL_CRYPTO_LIB="$OPENSSL_LIB_DIR/libcrypto.a"
    OPENSSL_SSL_LIB="$OPENSSL_LIB_DIR/libssl.a"

    if [ ! -f "$OPENSSL_CRYPTO_LIB" ] || [ ! -f "$OPENSSL_SSL_LIB" ]; then
        echo "Error: OpenSSL static libraries not found in $OPENSSL_LIB_DIR"
        exit 1
    fi
    if [ "$USE_QUICTLS" = "1" ]; then
        if ! grep -q "SSL_provide_quic_data" "$OPENSSL_INCLUDE_DIR/openssl/ssl.h" 2>/dev/null; then
            echo "Error: OpenSSL at $OPENSSL_INCLUDE_DIR does not include QUIC APIs (use QuicTLS)."
            exit 1
        fi
    fi

    CMAKE_ARGS+=(
        -DENABLE_WOLFSSL=OFF
        -DENABLE_OPENSSL=ON
        -DOPENSSL_ROOT_DIR="$OPENSSL_PATH"
        -DOPENSSL_INCLUDE_DIR="$OPENSSL_INCLUDE_DIR"
        -DOPENSSL_CRYPTO_LIBRARY="$OPENSSL_CRYPTO_LIB"
        -DOPENSSL_SSL_LIBRARY="$OPENSSL_SSL_LIB"
        -DOPENSSL_LIBRARIES="$OPENSSL_SSL_LIB;$OPENSSL_CRYPTO_LIB"
    )
    [ "$USE_QUICTLS" = "1" ] && CMAKE_ARGS+=( -DENABLE_QUICTLS=ON -DHAVE_SSL_PROVIDE_QUIC_DATA=1 -DHAVE_SSL_SET_QUIC_TLS_CBS=0 )
else
    CMAKE_ARGS+=( -DENABLE_WOLFSSL=OFF -DENABLE_OPENSSL=OFF )
fi
fi

echo ""
echo "Configuring CMake..."
cmake "$NGTCP2_SOURCE_DIR" "${CMAKE_ARGS[@]}"

echo ""
echo "Building ngtcp2..."
cmake --build . --config "$BUILD_TYPE" -j$(nproc 2>/dev/null || sysctl -n hw.ncpu)

echo ""
echo "Installing..."
cmake --install .

echo ""
echo "Build complete!"
echo "Library: $INSTALL_PREFIX/lib/libngtcp2.a"
echo "Headers: $INSTALL_PREFIX/include"
