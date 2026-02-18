#!/bin/bash
#
# Build script for OpenSSL on iOS
#
# This script builds OpenSSL 3.0+ as a static library for iOS.
# It requires:
# - Xcode 14+ (for iOS 15+)
# - iOS SDK 15.0+
#
# Usage:
#   ./build-openssl.sh [--arch ARCH] [--sdk SDK] [--version VERSION] [--quictls] [--quictls-branch BRANCH]
#
# Example:
#   ./build-openssl.sh --arch arm64 --sdk iphoneos --version 3.2.0 --quictls
#

set -e

# Default values: PROJECT_DIR = plugin root (where build-native.sh lives)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -z "$PROJECT_DIR" ]; then
    if [ -f "$SCRIPT_DIR/../package.json" ]; then
        PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    else
        PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    fi
fi
# Dependencies live in plugin root / deps (clone if missing)
DEPS_DIR="${PROJECT_DIR}/deps"
[ -f "$PROJECT_DIR/deps-versions.sh" ] && . "$PROJECT_DIR/deps-versions.sh"
DEFAULT_OPENSSL_SOURCE_DIR="${DEPS_DIR}/openssl"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.2.0}"
USE_QUICTLS="${USE_QUICTLS:-1}"
QUICTLS_BRANCH="${QUICTLS_BRANCH:-openssl-3.2}"
ARCH="${ARCH:-arm64}"
SDK="${SDK:-iphoneos}"
IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-15.0}"
INSTALL_PREFIX="${INSTALL_PREFIX:-$(pwd)/install/openssl-ios}"

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
        --ios-deployment-target)
            IOS_DEPLOYMENT_TARGET="$2"
            shift 2
            ;;
        --prefix)
            INSTALL_PREFIX="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--arch ARCH] [--sdk SDK] [--version VERSION] [--quictls] [--quictls-branch BRANCH]"
            exit 1
            ;;
    esac
done

# Check prerequisites
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

if [ "$USE_QUICTLS" = "1" ]; then
    echo "Building quictls ($QUICTLS_BRANCH) for iOS"
else
    echo "Building OpenSSL $OPENSSL_VERSION for iOS"
fi
echo "  Architecture: $ARCH"
echo "  SDK: $SDK"
echo "  SDK Path: $IOS_SDK_PATH"
echo "  Deployment Target: iOS $IOS_DEPLOYMENT_TARGET"
echo "  Install Prefix: $INSTALL_PREFIX"

# Check if OpenSSL/quictls source exists (quictls = new QuicTLS project; URL/commit from deps-versions.sh / ref-code/VERSION.txt)
if [ "$USE_QUICTLS" = "1" ]; then
    OPENSSL_SOURCE_DIR="${OPENSSL_SOURCE_DIR:-$DEFAULT_OPENSSL_SOURCE_DIR}"
    OPENSSL_REPO_URL="${QUICTLS_REPO_URL:-https://github.com/quictls/quictls.git}"
    OPENSSL_REPO_BRANCH="$QUICTLS_BRANCH"
else
    OPENSSL_SOURCE_DIR="${OPENSSL_SOURCE_DIR:-$DEFAULT_OPENSSL_SOURCE_DIR}"
    OPENSSL_REPO_URL="https://github.com/openssl/openssl.git"
    OPENSSL_REPO_BRANCH="openssl-$OPENSSL_VERSION"
fi
# If existing clone is from a different repo (e.g. old quictls/openssl), remove so we clone correct URL
if [ "$USE_QUICTLS" = "1" ] && [ -d "$OPENSSL_SOURCE_DIR/.git" ]; then
    CURRENT_ORIGIN=$(cd "$OPENSSL_SOURCE_DIR" && git config --get remote.origin.url 2>/dev/null || true)
    WANTED_QUICTLS="quictls/quictls"
    if [ -n "$CURRENT_ORIGIN" ] && ! echo "$CURRENT_ORIGIN" | grep -q "$WANTED_QUICTLS"; then
        echo "Existing clone is from $CURRENT_ORIGIN; re-cloning from $OPENSSL_REPO_URL"
        rm -rf "$OPENSSL_SOURCE_DIR"
    fi
fi
if [ ! -d "$OPENSSL_SOURCE_DIR" ]; then
    echo "OpenSSL source not found. Cloning..."
    if [ -n "$OPENSSL_COMMIT" ]; then
        git clone "$OPENSSL_REPO_URL" "$OPENSSL_SOURCE_DIR" || { echo "Error: Failed to clone OpenSSL"; exit 1; }
    else
        git clone --depth 1 --branch "$OPENSSL_REPO_BRANCH" \
            "$OPENSSL_REPO_URL" "$OPENSSL_SOURCE_DIR" || \
        git clone --depth 1 "$OPENSSL_REPO_URL" "$OPENSSL_SOURCE_DIR"
    fi
fi
if [ -n "$OPENSSL_COMMIT" ] && [ -d "$OPENSSL_SOURCE_DIR/.git" ]; then
    echo "Pinning OpenSSL to commit $OPENSSL_COMMIT"
    (cd "$OPENSSL_SOURCE_DIR" && git fetch origin main 2>/dev/null; git checkout "$OPENSSL_COMMIT") || {
        echo "Error: Failed to checkout OpenSSL commit $OPENSSL_COMMIT"
        exit 1
    }
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

# Set up environment for iOS cross-compilation
IOS_CC=$(xcrun --sdk "$SDK" --find clang)
IOS_AR=$(xcrun --sdk "$SDK" --find ar)
IOS_RANLIB=$(xcrun --sdk "$SDK" --find ranlib)

# Set compiler flags with correct sysroot
IOS_CFLAGS="-arch $ARCH -isysroot $IOS_SDK_PATH -mios-version-min=$IOS_DEPLOYMENT_TARGET -fno-common"

# Determine platform name based on architecture and SDK
if [ "$SDK" = "iphonesimulator" ]; then
    case "$ARCH" in
        arm64)
            PLATFORM="iossimulator-arm64-xcrun"
            ;;
        x86_64)
            PLATFORM="iossimulator-xcrun"
            ;;
        *)
            echo "Error: Unsupported simulator architecture: $ARCH"
            exit 1
            ;;
    esac
else
    case "$ARCH" in
        arm64)
            PLATFORM="ios64-xcrun"
            ;;
        armv7)
            PLATFORM="ios-xcrun"
            ;;
        *)
            echo "Error: Unsupported device architecture: $ARCH"
            exit 1
            ;;
    esac
fi

# Check if platform is available, fallback to ios64-cross if not
if ! ./Configure list | grep -q "^$PLATFORM\$"; then
    echo "Warning: Platform $PLATFORM not found, trying ios64-cross..."
    if [ "$ARCH" = "arm64" ] && [ "$SDK" != "iphonesimulator" ]; then
        PLATFORM="ios64-cross"
        # For ios64-cross, we need to set environment variables properly
        export CROSS_TOP="$IOS_SDK_PATH/.."
        export CROSS_SDK=$(basename "$IOS_SDK_PATH")
        export CC="$IOS_CC $IOS_CFLAGS"
    else
        echo "Error: Cannot determine appropriate platform for $ARCH on $SDK"
        exit 1
    fi
else
    # Use xcrun targets which handle sysroot automatically
    export CC="$IOS_CC"
    export CFLAGS="$IOS_CFLAGS"
fi

export AR="$IOS_AR"
export RANLIB="$IOS_RANLIB"

# Clean previous build if it exists (important for QUIC support)
echo ""
echo "Cleaning previous OpenSSL build (if any)..."
if [ -f "Makefile" ] || [ -f "configdata.pm" ]; then
    make distclean 2>/dev/null || true
    # Also remove any generated config files
    rm -f configdata.pm Makefile 2>/dev/null || true
fi

# Configure OpenSSL
echo ""
echo "Configuring OpenSSL for $PLATFORM with QUIC support..."
# OpenSSL uses "enable-quic" (not "quic") for QUIC support.
QUIC_OPTION="enable-quic"
if [ "$PLATFORM" = "ios64-cross" ]; then
    # For ios64-cross, set environment variables that OpenSSL expects
    export CROSS_TOP="$(dirname "$(dirname "$IOS_SDK_PATH")")"
    export CROSS_SDK="$(basename "$IOS_SDK_PATH")"
    export BUILD_TOOL="${IOS_CC%/*}"
    
    ./Configure "$PLATFORM" \
        --prefix="$INSTALL_PREFIX" \
        --openssldir="$INSTALL_PREFIX/ssl" \
        no-shared \
        no-tests \
        no-asm \
        "$QUIC_OPTION" \
        -mios-version-min="$IOS_DEPLOYMENT_TARGET"
    
    # Fix the Makefile to ensure correct sysroot is used
    if [ -f "Makefile" ]; then
        echo "Fixing Makefile to use correct sysroot..."
        
        # Use Python for more reliable text processing (heredoc quoted so bash does not parse parentheses)
        export IOS_SDK_PATH
        python3 << 'EOFPY'
import re
import sys
import os

sdk_path = os.environ.get('IOS_SDK_PATH', '')
makefile_path = "Makefile"

# Read the Makefile
with open(makefile_path, 'r') as f:
    content = f.read()

# Fix 1: Replace incorrect sysroot paths
content = re.sub(r'-isysroot\s+/SDKs/', f'-isysroot {sdk_path}', content)
content = re.sub(r'-isysroot\s+\$\(CROSS_TOP\)/SDKs/\$\(CROSS_SDK\)', f'-isysroot {sdk_path}', content)

# Fix 2: Fix cases where -isysroot is missing its path argument
# Pattern: -isysroot followed by whitespace and then a flag starting with -
# This is the critical fix
def fix_missing_sysroot(match):
    flag = match.group(1)
    return f'-isysroot {sdk_path} {flag}'

# Apply fix multiple times to catch all instances
for _ in range(10):
    old_content = content
    # Match: -isysroot followed by whitespace, then a flag starting with -
    content = re.sub(r'-isysroot\s+(-[^\s]+)', fix_missing_sysroot, content)
    if old_content == content:
        break  # No more changes

# Fix 3: Remove duplicate -isysroot arguments (keep only the first)
content = re.sub(r'-isysroot\s+([^\s]+)\s+-isysroot\s+([^\s]+)', r'-isysroot \1', content)

# Fix 4: Remove standalone SDK paths (not part of -isysroot)
# But be careful not to remove the path when it's part of -isysroot
def remove_standalone_sdk(match):
    before = match.group(1)
    after = match.group(2) if match.group(2) else ''
    # Only remove if it's not preceded by -isysroot
    if not before.rstrip().endswith('-isysroot'):
        return before + after
    return match.group(0)

content = re.sub(r'([^-])\s+' + re.escape(sdk_path) + r'(\s|$)', remove_standalone_sdk, content)

# Fix 5: Fix variable assignments that might have issues
# Fix CFLAGS, LDFLAGS, LDCMD variables
for var in ['CFLAGS', 'LDFLAGS', 'LDCMD', 'CC', 'CXX']:
    # Remove duplicate -isysroot in variable assignments
    pattern = rf'({var}=[^=]*?)-isysroot\s+[^\s]+\s+-isysroot\s+[^\s]+'
    replacement = rf'\1-isysroot {sdk_path}'
    content = re.sub(pattern, replacement, content)
    
    # Ensure -isysroot has path in variable assignments
    pattern = rf'({var}=[^=]*?)-isysroot\s+(-[^\s]+)'
    replacement = rf'\1-isysroot {sdk_path} \2'
    content = re.sub(pattern, replacement, content)

# Write the fixed Makefile
with open(makefile_path, 'w') as f:
    f.write(content)

# Verify fix
if re.search(r'-isysroot\s+-[a-zA-Z]', content):
    print("Warning: Some -isysroot flags may still be missing paths", file=sys.stderr)
    sys.exit(1)

print("Makefile fixed successfully")
EOFPY
        
        if [ $? -ne 0 ]; then
            echo "Error: Failed to fix Makefile"
            exit 1
        fi
    fi
else
    ./Configure "$PLATFORM" \
        --prefix="$INSTALL_PREFIX" \
        --openssldir="$INSTALL_PREFIX/ssl" \
        no-shared \
        no-tests \
        no-asm \
        "$QUIC_OPTION"
fi

# Verify QUIC support was enabled
echo ""
echo "Verifying QUIC support in OpenSSL configuration..."
if [ -f "configdata.pm" ]; then
    if grep -q "quic" configdata.pm 2>/dev/null; then
        echo "✓ QUIC support is enabled in OpenSSL configuration"
        # Show the QUIC-related configuration
        grep -i quic configdata.pm 2>/dev/null | head -3
    else
        echo "Warning: QUIC support may not be enabled. Checking configdata.pm..."
        grep -i quic configdata.pm 2>/dev/null || echo "QUIC not found in configdata.pm"
    fi
else
    echo "Warning: configdata.pm not found, cannot verify QUIC support"
fi

# Build
echo ""
echo "Building OpenSSL..."
# Build only the static libraries we need (libssl.a and libcrypto.a)
# We'll build everything but use -k (keep going) to continue even if some targets fail
# This allows us to get the libraries even if providers/apps have linking issues
echo "Building libraries (this may show errors for providers/apps, which is OK)..."
make -k -j$(sysctl -n hw.ncpu) || true

# Verify that the required libraries were built
if [ ! -f "libcrypto.a" ] || [ ! -f "libssl.a" ]; then
    echo "Error: Required libraries were not built"
    echo "Attempting to build libraries directly..."
    # Try building just the libraries
    make libcrypto.a libssl.a -j$(sysctl -n hw.ncpu) || {
        echo "Error: Failed to build libcrypto.a and libssl.a"
        exit 1
    }
fi

echo "Successfully built libcrypto.a and libssl.a"

# Install
echo ""
echo "Installing OpenSSL..."
# install_sw installs software (libraries and headers) without building
# Use -k to continue even if some parts fail
make -k install_sw || {
    echo "Warning: install_sw had some errors, but checking if libraries were installed..."
    # Manually copy libraries if install failed
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
echo "Syncing artifacts to ios/libs and ios/include..."
LIBS_DIR="$SCRIPT_DIR/libs"
INCLUDE_DIR="$SCRIPT_DIR/include"
mkdir -p "$LIBS_DIR" "$INCLUDE_DIR"
if [ -f "$INSTALL_PREFIX/lib/libssl.a" ] && [ -f "$INSTALL_PREFIX/lib/libcrypto.a" ]; then
    cp "$INSTALL_PREFIX/lib/libssl.a" "$INSTALL_PREFIX/lib/libcrypto.a" "$LIBS_DIR/"
fi
if [ -d "$INSTALL_PREFIX/include/openssl" ]; then
    cp -R "$INSTALL_PREFIX/include/openssl" "$INCLUDE_DIR/"
fi

echo ""
echo "OpenSSL build complete!"
echo "Installation directory: $INSTALL_PREFIX"
echo "Libraries: $INSTALL_PREFIX/lib"
echo "Headers: $INSTALL_PREFIX/include"
