// swift-tools-version: 6.0

import PackageDescription

// The swim kit: the pool lengths, the automatic set/rest split, heart-rate
// zones and the clock formats the Swim watch app shows.
//
// **Why this is its own package.** The same split as RowingKit: everything that
// is arithmetic lives here, where `swift test` runs on kevg10, and the watch
// app keeps only what needs HealthKit and a screen — which only the macOS
// runner can compile. Nothing here imports anything but Foundation.
let package = Package(
    name: "SwimKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v11),
    ],
    products: [
        .library(name: "SwimKit", targets: ["SwimKit"]),
    ],
    targets: [
        .target(name: "SwimKit"),
        .testTarget(name: "SwimKitTests", dependencies: ["SwimKit"]),
    ]
)
