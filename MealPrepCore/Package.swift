// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MealPrepCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "MealPrepCore", targets: ["MealPrepCore"]),
        .executable(name: "mealprep-demo", targets: ["MealPrepDemo"])
    ],
    targets: [
        .target(
            name: "MealPrepCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "MealPrepDemo",
            dependencies: ["MealPrepCore"]
        ),
        .testTarget(
            name: "MealPrepCoreTests",
            dependencies: ["MealPrepCore"]
        )
    ]
)
