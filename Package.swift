// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "NetworkMetricsSDK",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "NetworkMetricsSDK", targets: ["NetworkMetricsSDK"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "NetworkMetricsSDK",
            dependencies: [],
            path: "Sources/NetworkMetricsSDK"
        ),
    ]
)
