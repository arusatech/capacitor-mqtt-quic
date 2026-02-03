#!/bin/bash

# Build script for capacitor-mqtt-quic plugin
# By default builds WolfSSL (TLS 1.3 + QUIC), then nghttp3, then ngtcp2 for iOS and Android.
# Set USE_WOLFSSL=0 to use QuicTLS instead of WolfSSL. Default is controlled by deps-versions.sh.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get script directory and project root (plugin root = where this script lives)
# Dependency sources (openssl, nghttp3, ngtcp2) are cloned into PROJECT_DIR/deps/ if missing
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$SCRIPT_DIR}"
# Default TLS backend: WolfSSL (single source of truth)
[ -f "$PROJECT_DIR/deps-versions.sh" ] && . "$PROJECT_DIR/deps-versions.sh"
USE_WOLFSSL="${USE_WOLFSSL:-1}"

# Check if we're on macOS for iOS builds
check_macos() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        print_warning "iOS builds require macOS. Skipping iOS build."
        return 1
    fi
    return 0
}

# Check if Android SDK is available
check_android_sdk() {
    if [ -z "$ANDROID_HOME" ] && [ -z "$ANDROID_SDK_ROOT" ]; then
        print_warning "Android SDK not found. Please set ANDROID_HOME or ANDROID_SDK_ROOT."
        print_warning "Skipping Android build."
        return 1
    fi
    return 0
}

# Detect NDK path: ndk/<version>/build/cmake/android.toolchain.cmake
detect_ndk() {
    local sdk="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
    local ndk_root="$sdk/ndk"
    
    # Also check macOS default location
    if [ ! -d "$ndk_root" ] && [ -d "$HOME/Library/Android/sdk/ndk" ]; then
        ndk_root="$HOME/Library/Android/sdk/ndk"
    fi
    
    if [ ! -d "$ndk_root" ]; then
        echo ""
        return 1
    fi
    
    local latest=""
    local latest_ver=0
    for v in "$ndk_root"/*; do
        [ -d "$v" ] || continue
        local base=$(basename "$v")
        if [[ "$base" =~ ^[0-9] ]]; then
            local ver=$(echo "$base" | sed 's/[^0-9]//g' | head -c 10)
            ver=${ver:-0}
            if [ "$ver" -gt "$latest_ver" ] 2>/dev/null; then
                latest_ver=$ver
                latest=$v
            fi
        fi
    done
    
    if [ -n "$latest" ] && [ -f "$latest/build/cmake/android.toolchain.cmake" ]; then
        echo "$latest"
        return 0
    fi
    echo ""
    return 1
}

# Build iOS libraries (WolfSSL or QuicTLS → nghttp3 → ngtcp2)
build_ios() {
    USE_WOLFSSL="${USE_WOLFSSL:-1}"
    if [ "$USE_WOLFSSL" = "1" ]; then
        print_status "Building iOS libraries (WolfSSL → nghttp3 → ngtcp2)..."
    else
        print_status "Building iOS libraries (OpenSSL/QuicTLS → nghttp3 → ngtcp2)..."
    fi
    
    if ! check_macos; then
        return 1
    fi
    
    export PROJECT_DIR="$PROJECT_DIR"
    export USE_WOLFSSL="$USE_WOLFSSL"
    cd "$PROJECT_DIR/ios"
    
    if [ "$USE_WOLFSSL" = "1" ]; then
        print_status "Step 1/3: Building WolfSSL (TLS 1.3 + QUIC) for iOS..."
        if [ -f "./build-wolfssl.sh" ]; then
            ./build-wolfssl.sh || {
                print_error "Failed to build WolfSSL for iOS"
                return 1
            }
            print_success "WolfSSL built for iOS"
        else
            print_error "build-wolfssl.sh not found in ios/"
            return 1
        fi
    else
        print_status "Step 1/3: Building OpenSSL (quictls) for iOS..."
        if [ -f "./build-openssl.sh" ]; then
            ./build-openssl.sh --quictls || {
                print_error "Failed to build OpenSSL for iOS"
                return 1
            }
            print_success "OpenSSL (quictls) built for iOS"
        else
            print_error "build-openssl.sh not found in ios/"
            return 1
        fi
    fi
    
    print_status "Step 2/3: Building nghttp3 for iOS..."
    if [ -f "./build-nghttp3.sh" ]; then
        ./build-nghttp3.sh || {
            print_error "Failed to build nghttp3 for iOS"
            return 1
        }
        print_success "nghttp3 built for iOS"
    else
        print_error "build-nghttp3.sh not found in ios/"
        return 1
    fi
    
    print_status "Step 3/3: Building ngtcp2 for iOS (device)..."
    if [ -f "./build-ngtcp2.sh" ]; then
        if [ "$USE_WOLFSSL" = "1" ]; then
            ./build-ngtcp2.sh --wolfssl-path ./install/wolfssl-ios || {
                print_error "Failed to build ngtcp2 for iOS"
                return 1
            }
        else
            ./build-ngtcp2.sh --quictls || {
                print_error "Failed to build ngtcp2 for iOS"
                return 1
            }
        fi
        print_success "ngtcp2 built for iOS (device)"
    else
        print_error "build-ngtcp2.sh not found in ios/"
        return 1
    fi

    if [ "$USE_WOLFSSL" = "1" ]; then
        print_status "Step 4/4: Building iOS Simulator libraries (WolfSSL → nghttp3 → ngtcp2)..."
        export ARCH=arm64
        export SDK=iphonesimulator
        ./build-wolfssl.sh --arch arm64 --sdk iphonesimulator || {
            print_error "Failed to build WolfSSL for iOS Simulator"
            return 1
        }
        ./build-nghttp3.sh --arch arm64 --sdk iphonesimulator || {
            print_error "Failed to build nghttp3 for iOS Simulator"
            return 1
        }
        ./build-ngtcp2.sh --wolfssl-path ./install/wolfssl-ios-simulator --arch arm64 --sdk iphonesimulator || {
            print_error "Failed to build ngtcp2 for iOS Simulator"
            return 1
        }
        print_success "iOS Simulator libraries built (arm64)"

        # Optional x86_64 simulator slice (helps Xcode builds that request both archs)
        print_status "Step 4/4: Building iOS Simulator x86_64 libraries (WolfSSL → nghttp3 → ngtcp2)..."
        export ARCH=x86_64
        export SDK=iphonesimulator
        export LIBS_DIR="$PROJECT_DIR/ios/libs-simulator-x86_64"
        export INSTALL_PREFIX="$PROJECT_DIR/ios/install/wolfssl-ios-simulator-x86_64"
        ./build-wolfssl.sh --arch x86_64 --sdk iphonesimulator --prefix "$INSTALL_PREFIX" || {
            print_error "Failed to build WolfSSL for iOS Simulator (x86_64)"
            return 1
        }
        ./build-nghttp3.sh --arch x86_64 --sdk iphonesimulator || {
            print_error "Failed to build nghttp3 for iOS Simulator (x86_64)"
            return 1
        }
        ./build-ngtcp2.sh --wolfssl-path ./install/wolfssl-ios-simulator-x86_64 --arch x86_64 --sdk iphonesimulator || {
            print_error "Failed to build ngtcp2 for iOS Simulator (x86_64)"
            return 1
        }
        print_success "iOS Simulator libraries built (x86_64)"
    else
        print_warning "iOS Simulator build skipped (device-only). Use USE_WOLFSSL=1 for device+simulator xcframework."
    fi

    cd "$PROJECT_DIR"
    print_success "All iOS libraries (device + simulator) built successfully!"
    print_status "Next: cd ios && ./create-xcframework.sh  (creates MqttQuicLibs.xcframework for SPM / Simulator)"
}

# Build Android libraries (WolfSSL or QuicTLS → nghttp3 → ngtcp2)
build_android() {
    USE_WOLFSSL="${USE_WOLFSSL:-1}"
    if [ "$USE_WOLFSSL" = "1" ]; then
        print_status "Building Android libraries (WolfSSL → nghttp3 → ngtcp2)..."
    else
        print_status "Building Android libraries (OpenSSL/QuicTLS → nghttp3 → ngtcp2)..."
    fi
    
    if ! check_android_sdk; then
        return 1
    fi
    
    ANDROID_NDK=$(detect_ndk)
    if [ -z "$ANDROID_NDK" ]; then
        print_error "Android NDK not found. Install NDK via Android Studio (SDK Manager → NDK)."
        return 1
    fi
    print_status "Using NDK: $ANDROID_NDK"
    
    export PROJECT_DIR="$PROJECT_DIR"
    export ANDROID_NDK="$ANDROID_NDK"
    export USE_WOLFSSL="$USE_WOLFSSL"
    ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"
    ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-21}"
    cd "$PROJECT_DIR/android"
    
    if [ "$USE_WOLFSSL" = "1" ]; then
        print_status "Step 1/3: Building WolfSSL (TLS 1.3 + QUIC) for Android ($ANDROID_ABI)..."
        if [ -f "./build-wolfssl.sh" ]; then
            ./build-wolfssl.sh --ndk-path "$ANDROID_NDK" --abi "$ANDROID_ABI" --platform "$ANDROID_PLATFORM" || {
                print_error "Failed to build WolfSSL for Android"
                return 1
            }
            print_success "WolfSSL built for Android ($ANDROID_ABI)"
        else
            print_error "build-wolfssl.sh not found in android/"
            return 1
        fi
    else
        print_status "Step 1/3: Building OpenSSL (quictls) for Android ($ANDROID_ABI)..."
        if [ -f "./build-openssl.sh" ]; then
            ./build-openssl.sh --ndk-path "$ANDROID_NDK" --abi "$ANDROID_ABI" --platform "$ANDROID_PLATFORM" --quictls || {
                print_error "Failed to build OpenSSL for Android"
                return 1
            }
            print_success "OpenSSL (quictls) built for Android ($ANDROID_ABI)"
        else
            print_error "build-openssl.sh not found in android/"
            return 1
        fi
    fi
    
    print_status "Step 2/3: Building nghttp3 for Android ($ANDROID_ABI)..."
    if [ -f "./build-nghttp3.sh" ]; then
        ./build-nghttp3.sh --ndk-path "$ANDROID_NDK" --abi "$ANDROID_ABI" --platform "$ANDROID_PLATFORM" || {
            print_error "Failed to build nghttp3 for Android"
            return 1
        }
        print_success "nghttp3 built for Android ($ANDROID_ABI)"
    else
        print_error "build-nghttp3.sh not found in android/"
        return 1
    fi
    
    print_status "Step 3/3: Building ngtcp2 for Android ($ANDROID_ABI)..."
    if [ -f "./build-ngtcp2.sh" ]; then
        if [ "$USE_WOLFSSL" = "1" ]; then
            ./build-ngtcp2.sh --ndk-path "$ANDROID_NDK" --abi "$ANDROID_ABI" --platform "$ANDROID_PLATFORM" --wolfssl-path ./install/wolfssl-android || {
                print_error "Failed to build ngtcp2 for Android"
                return 1
            }
        else
            ./build-ngtcp2.sh --ndk-path "$ANDROID_NDK" --abi "$ANDROID_ABI" --platform "$ANDROID_PLATFORM" --quictls || {
                print_error "Failed to build ngtcp2 for Android"
                return 1
            }
        fi
        print_success "ngtcp2 built for Android ($ANDROID_ABI)"
    else
        print_error "build-ngtcp2.sh not found in android/"
        return 1
    fi
    
    cd "$PROJECT_DIR"
    print_success "All Android libraries built successfully for $ANDROID_ABI!"
}

# Main build function
main() {
    print_status "Starting capacitor-mqtt-quic native library build..."
    print_status "Project directory: $PROJECT_DIR"
    
    # Check dependencies
    if ! command -v cmake &> /dev/null; then
        print_error "CMake is required but not installed"
        exit 1
    fi
    
    if ! command -v make &> /dev/null; then
        print_error "Make is required but not installed"
        exit 1
    fi
    
    # Parse arguments
    BUILD_IOS=true
    BUILD_ANDROID=true
    ANDROID_ABI="arm64-v8a"
    ANDROID_PLATFORM="android-21"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ios-only)
                BUILD_ANDROID=false
                shift
                ;;
            --android-only)
                BUILD_IOS=false
                shift
                ;;
            --abi)
                ANDROID_ABI="$2"
                shift 2
                ;;
            --platform)
                ANDROID_PLATFORM="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --ios-only          Build only iOS libraries"
                echo "  --android-only      Build only Android libraries"
                echo "  --abi ABI           Android ABI (default: arm64-v8a)"
                echo "  --platform PLATFORM Android platform (default: android-21)"
                echo "  --help              Show this help message"
                echo ""
                echo "Environment variables:"
                echo "  PROJECT_DIR         Project root directory (default: script directory)"
                echo "  ANDROID_HOME        Android SDK path"
                echo "  ANDROID_SDK_ROOT    Alternative Android SDK path"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Build iOS
    if [ "$BUILD_IOS" = true ]; then
        if check_macos; then
            build_ios
        else
            print_warning "Skipping iOS build (requires macOS)"
        fi
    fi
    
    # Build Android
    if [ "$BUILD_ANDROID" = true ]; then
        if check_android_sdk; then
            build_android
        else
            print_warning "Skipping Android build (Android SDK not found)"
        fi
    fi
    
    print_success "Build completed successfully!"
    print_status ""
    print_status "Next steps:"
    print_status "  1. Run 'npm run build' to build TypeScript"
    print_status "  2. Run 'npx cap sync' in your app to sync native code"
    print_status "  3. Build your app with Xcode (iOS) or Android Studio (Android)"
}

# Run main function
main "$@"
