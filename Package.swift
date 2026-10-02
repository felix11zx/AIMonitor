// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIMonitor",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AIMonitorCore", targets: ["AIMonitorCore"]), .executable(name: "AIMonitor", targets: ["AIMonitor"])],
    targets: [
        .target(name: "AIMonitorCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "AIMonitor", dependencies: ["AIMonitorCore"]),
        .testTarget(name: "AIMonitorCoreTests", dependencies: ["AIMonitorCore"])
    ],
    swiftLanguageModes: [.v5]
)
