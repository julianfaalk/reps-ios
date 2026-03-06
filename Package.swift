// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WorkoutApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "WorkoutAppCore",
            targets: ["WorkoutAppCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0")
    ],
    targets: [
        .target(
            name: "WorkoutAppCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "WorkoutApp",
            sources: [
                "Models/AppSettings.swift",
                "Models/CardioSession.swift",
                "Models/Exercise.swift",
                "Models/PersonalRecord.swift",
                "Models/Schedule.swift",
                "Models/Template.swift",
                "Models/WorkoutActivityAttributes.swift",
                "Models/WorkoutSession.swift",
                "Services/DatabaseService.swift",
                "Services/WorkoutPlanGenerator.swift",
                "ViewModels/TodayViewModel.swift",
                "ViewModels/WorkoutViewModel.swift"
            ]),
        .testTarget(
            name: "WorkoutAppTests",
            dependencies: ["WorkoutAppCore"],
            path: "WorkoutAppTests"),
    ]
)
