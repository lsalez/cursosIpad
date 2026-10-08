// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Shared",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Shared",
            targets: ["Shared"]),
    ],
    targets: [
        .target(
            name: "Shared",
            path: "Sources/Shared"),
    ]
)
