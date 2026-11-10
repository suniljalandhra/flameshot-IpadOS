// swift-tools-version: 6.0
import PackageDescription

// EmberKit holds everything that defines the editor's behaviour (model,
// geometry, rendering, undo, capture frame storage). It has no UIKit
// dependency, so `swift test` runs it on a Mac without a simulator.
let package = Package(
    name: "EmberKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "EmberKit", targets: ["EmberKit"]),
    ],
    targets: [
        .target(name: "EmberKit"),
        .testTarget(name: "EmberKitTests", dependencies: ["EmberKit"]),
    ]
)
