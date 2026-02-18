cmake_minimum_required(VERSION 3.20)
project(ngtcp2_client)

# Set Android-specific flags
set(CMAKE_SYSTEM_NAME Android)
set(CMAKE_ANDROID_ARCH_ABI ${ANDROID_ABI})
set(CMAKE_ANDROID_NDK ${ANDROID_NDK})

# Android API level
if(NOT ANDROID_PLATFORM)
    set(ANDROID_PLATFORM android-21)
endif()

# WolfSSL path (same layout as iOS: TLS backend for ngtcp2). Override via -DWOLFSSL_ROOT_DIR=...
if(NOT WOLFSSL_ROOT_DIR)
    set(WOLFSSL_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../install/wolfssl-android" CACHE PATH "Path to WolfSSL for Android")
endif()
# Prefer ABI-specific subdir when present (e.g. when WOLFSSL_ROOT_DIR is passed as base path from Gradle)
if(EXISTS "${WOLFSSL_ROOT_DIR}/${ANDROID_ABI}")
    set(WOLFSSL_ROOT_DIR "${WOLFSSL_ROOT_DIR}/${ANDROID_ABI}" CACHE PATH "Path to WolfSSL for Android (ABI)" FORCE)
endif()
if(NOT WOLFSSL_INCLUDE_DIR AND EXISTS "${WOLFSSL_ROOT_DIR}/include")
    set(WOLFSSL_INCLUDE_DIR "${WOLFSSL_ROOT_DIR}/include")
endif()
if(NOT WOLFSSL_LIBRARY AND EXISTS "${WOLFSSL_ROOT_DIR}/lib/libwolfssl.a")
    set(WOLFSSL_LIBRARY "${WOLFSSL_ROOT_DIR}/lib/libwolfssl.a")
endif()
if(NOT WOLFSSL_LIBRARY OR NOT WOLFSSL_INCLUDE_DIR)
    message(FATAL_ERROR
        "WolfSSL not found at ${WOLFSSL_ROOT_DIR}. "
        "One-time fix (from your app project root): "
        "cd node_modules/@annadata/capacitor-mqtt-quic && "
        "./build-native.sh --android-only --abi ${ANDROID_ABI} "
        "(repeat for armeabi-v7a, x86_64). See plugin README 'Production / First-time build'.")
endif()

# ngtcp2 install/source directories (adjust as needed)
if(NOT NGTCP2_INSTALL_DIR)
    set(NGTCP2_INSTALL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../build/android-${ANDROID_ABI}/install" CACHE PATH "Path to ngtcp2 install")
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../../install/ngtcp2-android/${ANDROID_ABI}")
        set(NGTCP2_INSTALL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../install/ngtcp2-android/${ANDROID_ABI}" CACHE PATH "Path to ngtcp2 install (ABI)" FORCE)
    endif()
endif()
set(NGTCP2_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../ngtcp2" CACHE PATH "Path to ngtcp2 source")

# nghttp3 install/source directories (adjust as needed)
if(NOT NGHTTP3_INSTALL_DIR)
    set(NGHTTP3_INSTALL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../build/nghttp3-android-${ANDROID_ABI}/install" CACHE PATH "Path to nghttp3 install")
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../../install/nghttp3-android/${ANDROID_ABI}")
        set(NGHTTP3_INSTALL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../install/nghttp3-android/${ANDROID_ABI}" CACHE PATH "Path to nghttp3 install (ABI)" FORCE)
    endif()
endif()
set(NGHTTP3_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../nghttp3" CACHE PATH "Path to nghttp3 source")

# Prefer ABI-specific subdir when install dirs are passed as base path from Gradle
if(EXISTS "${NGTCP2_INSTALL_DIR}/${ANDROID_ABI}")
    set(NGTCP2_INSTALL_DIR "${NGTCP2_INSTALL_DIR}/${ANDROID_ABI}" CACHE PATH "Path to ngtcp2 install (ABI)" FORCE)
endif()
if(EXISTS "${NGHTTP3_INSTALL_DIR}/${ANDROID_ABI}")
    set(NGHTTP3_INSTALL_DIR "${NGHTTP3_INSTALL_DIR}/${ANDROID_ABI}" CACHE PATH "Path to nghttp3 install (ABI)" FORCE)
endif()

# Prefer installed libraries (WolfSSL backend: libngtcp2_crypto_wolfssl.a), fallback to source build
set(NGTCP2_INCLUDE_DIR "")
set(NGTCP2_LIBRARY "")
set(NGTCP2_CRYPTO_LIBRARY "")
if(EXISTS "${NGTCP2_INSTALL_DIR}/include/ngtcp2/ngtcp2.h")
    set(NGTCP2_INCLUDE_DIR "${NGTCP2_INSTALL_DIR}/include")
    if(EXISTS "${NGTCP2_INSTALL_DIR}/lib/libngtcp2.a")
        set(NGTCP2_LIBRARY "${NGTCP2_INSTALL_DIR}/lib/libngtcp2.a")
    elseif(EXISTS "${NGTCP2_INSTALL_DIR}/lib/libngtcp2.so")
        set(NGTCP2_LIBRARY "${NGTCP2_INSTALL_DIR}/lib/libngtcp2.so")
    endif()
    if(EXISTS "${NGTCP2_INSTALL_DIR}/lib/libngtcp2_crypto_wolfssl.a")
        set(NGTCP2_CRYPTO_LIBRARY "${NGTCP2_INSTALL_DIR}/lib/libngtcp2_crypto_wolfssl.a")
    elseif(EXISTS "${NGTCP2_INSTALL_DIR}/lib/libngtcp2_crypto_wolfssl.so")
        set(NGTCP2_CRYPTO_LIBRARY "${NGTCP2_INSTALL_DIR}/lib/libngtcp2_crypto_wolfssl.so")
    endif()
else()
    if(NOT EXISTS "${NGTCP2_SOURCE_DIR}/lib/includes/ngtcp2/ngtcp2.h" AND NOT EXISTS "${NGTCP2_SOURCE_DIR}/lib/ngtcp2.h")
        message(WARNING "ngtcp2 source not found at ${NGTCP2_SOURCE_DIR}")
        message(WARNING "Please set NGTCP2_SOURCE_DIR or clone ngtcp2:")
        message(WARNING "  git clone https://github.com/ngtcp2/ngtcp2.git")
    endif()
    if(EXISTS "${NGTCP2_SOURCE_DIR}/CMakeLists.txt")
        add_subdirectory(${NGTCP2_SOURCE_DIR} ngtcp2_lib)
    endif()
endif()

set(NGHTTP3_INCLUDE_DIR "")
set(NGHTTP3_LIBRARY "")
if(EXISTS "${NGHTTP3_INSTALL_DIR}/include/nghttp3/nghttp3.h")
    set(NGHTTP3_INCLUDE_DIR "${NGHTTP3_INSTALL_DIR}/include")
    if(EXISTS "${NGHTTP3_INSTALL_DIR}/lib/libnghttp3.a")
        set(NGHTTP3_LIBRARY "${NGHTTP3_INSTALL_DIR}/lib/libnghttp3.a")
    elseif(EXISTS "${NGHTTP3_INSTALL_DIR}/lib/libnghttp3.so")
        set(NGHTTP3_LIBRARY "${NGHTTP3_INSTALL_DIR}/lib/libnghttp3.so")
    endif()
else()
    if(NOT EXISTS "${NGHTTP3_SOURCE_DIR}/lib/includes/nghttp3/nghttp3.h" AND NOT EXISTS "${NGHTTP3_SOURCE_DIR}/lib/nghttp3.h")
        message(WARNING "nghttp3 source not found at ${NGHTTP3_SOURCE_DIR}")
        message(WARNING "Please set NGHTTP3_SOURCE_DIR or clone nghttp3:")
        message(WARNING "  git clone https://github.com/ngtcp2/nghttp3.git")
    endif()
    if(EXISTS "${NGHTTP3_SOURCE_DIR}/CMakeLists.txt")
        add_subdirectory(${NGHTTP3_SOURCE_DIR} nghttp3_lib)
    endif()
endif()

# JNI source files
set(JNI_SOURCES
    ngtcp2_jni.cpp
)

# Create shared library
add_library(ngtcp2_client SHARED ${JNI_SOURCES})

# Include directories
target_include_directories(ngtcp2_client PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${NGTCP2_INCLUDE_DIR}
    ${NGHTTP3_INCLUDE_DIR}
    ${NGTCP2_SOURCE_DIR}/lib/includes
    ${NGHTTP3_SOURCE_DIR}/lib/includes
    ${WOLFSSL_INCLUDE_DIR}
)

# Link libraries: WolfSSL + ngtcp2 (same TLS backend as iOS)
target_link_libraries(ngtcp2_client PRIVATE
    ${WOLFSSL_LIBRARY}
    log
)

if(TARGET ngtcp2)
    target_link_libraries(ngtcp2_client PRIVATE ngtcp2)
elseif(NGTCP2_LIBRARY)
    target_link_libraries(ngtcp2_client PRIVATE ${NGTCP2_LIBRARY})
endif()

if(TARGET nghttp3)
    target_link_libraries(ngtcp2_client PRIVATE nghttp3)
elseif(NGHTTP3_LIBRARY)
    target_link_libraries(ngtcp2_client PRIVATE ${NGHTTP3_LIBRARY})
endif()

if(NGTCP2_CRYPTO_LIBRARY)
    target_link_libraries(ngtcp2_client PRIVATE ${NGTCP2_CRYPTO_LIBRARY})
endif()

# Compiler flags
target_compile_options(ngtcp2_client PRIVATE
    -Wall
    -Wextra
    -Wno-unused-parameter
    -fexceptions
    -frtti
)

# C++ standard
set_target_properties(ngtcp2_client PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
)
