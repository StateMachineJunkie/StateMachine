// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftFSM",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "SwiftFSM", targets: ["SwiftFSM"]),
    ],
    targets: [
        .target(
            name: "SwiftFSM",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiftFSMTests",
            dependencies: ["SwiftFSM"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
