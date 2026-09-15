// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "TrafficLightKit",
    platforms: [.macOS("27.0")],
    products: [.library(name: "TrafficLightKit", targets: ["TrafficLightKit"])],
    targets: [
        .target(
            name: "TrafficLightKit",
            path: "Sources",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "TrafficLightKitTests",
            dependencies: ["TrafficLightKit"],
            path: "Tests"
        )
    ]
)
