// swift-tools-version: 5.9
import PackageDescription

// MqttQuicPlugin iOS – Swift Package for Capacitor 8 (SPM).
// Requires Libs/MqttQuicLibs.xcframework. After building OpenSSL, ngtcp2, nghttp3
// (see build-openssl.sh, build-ngtcp2.sh, build-nghttp3.sh), run:
//   ./create-xcframework.sh
let package = Package(
    name: "MqttQuicPlugin",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "MqttQuicPlugin",
            targets: ["MqttQuicPlugin"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0")
    ],
    targets: [
        .binaryTarget(
            name: "MqttQuicLibs",
            path: "libs/MqttQuicLibs.xcframework"
        ),
        .target(
            name: "NGTCP2Bridge",
            dependencies: ["MqttQuicLibs"],
            path: "Sources/MqttQuicPlugin/QUIC",
            sources: ["NGTCP2Bridge.mm"],
            publicHeadersPath: ".",
            cxxSettings: [
                .define("NGTCP2_ENABLED"),
                .define("NGHTTP3_ENABLED"),
                .headerSearchPath("../../../include")
            ],
            linkerSettings: [
                .linkedLibrary("c++")
            ]
        ),
        .target(
            name: "MqttQuicPlugin",
            dependencies: [
                "NGTCP2Bridge",
                .product(name: "Capacitor", package: "capacitor-swift-pm")
            ],
            path: "Sources/MqttQuicPlugin",
            exclude: [
                "MQTT/MQTT5ReasonCodes.swift.rej",
                "QUIC/NGTCP2Bridge.mm",
                "QUIC/NGTCP2Bridge.h"
            ],
            resources: [.process("Resources")],
            swiftSettings: [
                .define("NGTCP2_ENABLED"),
                .define("NGHTTP3_ENABLED")
            ]
        )
    ]
)
