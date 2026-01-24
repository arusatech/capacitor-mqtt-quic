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

# Find required packages
find_package(OpenSSL REQUIRED)

# ngtcp2 source directory (adjust path as needed)
set(NGTCP2_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../ngtcp2" CACHE PATH "Path to ngtcp2 source")

# Check if ngtcp2 source exists
if(NOT EXISTS "${NGTCP2_SOURCE_DIR}/lib/ngtcp2.h")
    message(WARNING "ngtcp2 source not found at ${NGTCP2_SOURCE_DIR}")
    message(WARNING "Please set NGTCP2_SOURCE_DIR or clone ngtcp2:")
    message(WARNING "  git clone https://github.com/ngtcp2/ngtcp2.git")
endif()

# Add ngtcp2 as subdirectory (if available)
if(EXISTS "${NGTCP2_SOURCE_DIR}/CMakeLists.txt")
    add_subdirectory(${NGTCP2_SOURCE_DIR} ngtcp2_lib)
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
    ${NGTCP2_SOURCE_DIR}/lib/includes
    ${OpenSSL_INCLUDE_DIR}
)

# Link libraries
target_link_libraries(ngtcp2_client
    # ngtcp2 library (when built)
    # ngtcp2
    # OpenSSL
    ${OpenSSL_LIBRARIES}
    # Android log
    log
)

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
