// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZenmanageSwift",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(
            name: "Zenmanage",
            targets: ["Zenmanage"]
        ),
    ],
    targets: [
        .target(
            name: "Zenmanage"
        ),
        .testTarget(
            name: "ZenmanageTests",
            dependencies: ["Zenmanage"]
        ),
    ]
)