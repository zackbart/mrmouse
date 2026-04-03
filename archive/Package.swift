// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MrMouse",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MrMouse", targets: ["MrMouse"]),
        .library(name: "HIDPPCore", targets: ["HIDPPCore"]),
    ],
    targets: [
        .target(
            name: "HIDPPCore",
            path: "Sources/HIDPPCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .target(
            name: "EventEngine",
            dependencies: ["HIDPPCore", "Config"],
            path: "Sources/EventEngine",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
            ]
        ),
        .target(
            name: "Config",
            path: "Sources/Config"
        ),
        .executableTarget(
            name: "MrMouse",
            dependencies: ["HIDPPCore", "EventEngine", "Config"],
            path: "Sources/MrMouse",
            exclude: ["Info.plist"],
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "HIDPPCoreTests",
            dependencies: ["HIDPPCore", "Config"],
            path: "Tests/HIDPPCoreTests"
        ),
    ]
)
