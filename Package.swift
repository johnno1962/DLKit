// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DLKit",
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "DLKit",
            targets: ["DLKit"]),
        .library(
            name: "DLKitC",
            targets: ["DLKitC"]),
        .library(
            name: "DLKitD",
            targets: ["DLKitD"]),
        .library(
            name: "DLKitCD",
            targets: ["DLKitCD"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/johnno1962/fishhook",
                 .upToNextMinor(from: "1.2.0")),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "DLKit",
            dependencies: ["DLKitC", "fishhook"]),
        .target(
            name: "DLKitC",
            linkerSettings: [.linkedFramework("Foundation")]),
        .target(
            name: "DLKitD",
            dependencies: ["DLKitCD", .product(name: "fishhookD", package: "fishhook")],
            swiftSettings: [.define("DEBUG_ONLY")]),
        .target(
            name: "DLKitCD",
            dependencies: [.product(name: "fishhookD", package: "fishhook")],
            cSettings: [.define("DEBUG_ONLY")],
            linkerSettings: [.linkedFramework("Foundation")]),
        .testTarget(
            name: "DLKitTests",
            dependencies: ["DLKit"]),
    ]
)
