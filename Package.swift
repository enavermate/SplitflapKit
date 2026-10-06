// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SplitflapKit",
    // iOS, iPadOS and the Mac through Mac Catalyst. The planner's tests also run on a Mac and on
    // Linux: `swift test -Xswiftc -DSPLITFLAP_HOST_TESTS` (Sources/SplitflapKit/Platforms.swift).
    platforms: [
        .iOS(.v15),
        .macCatalyst(.v15),
    ],
    products: [
        .library(name: "SplitflapKit", targets: ["SplitflapKit"]),
        .library(name: "SplitflapPlanner", targets: ["SplitflapPlanner"]),
    ],
    targets: [
        .target(name: "SplitflapPlanner"),
        .target(name: "SplitflapKit", dependencies: ["SplitflapPlanner"]),
        .testTarget(
            name: "SplitflapPlannerTests",
            dependencies: ["SplitflapPlanner"],
            resources: [.copy("Resources")]
        ),
    ]
)
