// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "action-socket",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "action-socket",
            targets: ["action-socket"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "action-socket"
        ),
        .testTarget(
            name: "action-socketTests",
            dependencies: ["action-socket"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
