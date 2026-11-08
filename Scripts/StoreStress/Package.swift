// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StoreStress",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(name: "Sharingan", path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "StoreStress",
            dependencies: [
                .product(name: "SharinganCore", package: "Sharingan"),
            ],
            path: ".",
            exclude: ["Package.swift", "README.md"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]),
    ])
