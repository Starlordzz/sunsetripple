// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SunsetRipple",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "SunsetRipple",
            targets: ["SunsetRipple"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SunsetRipple",
            dependencies: [],
            path: "SunsetRipple"
        )
    ]
)

