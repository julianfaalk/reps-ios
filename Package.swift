// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WorkoutApp",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "WorkoutApp",
            targets: ["WorkoutApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0")
    ],
    targets: [
        .target(
            name: "WorkoutApp",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]),
    ]
)
