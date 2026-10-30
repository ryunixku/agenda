// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AgendaKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "AgendaCore", targets: ["AgendaCore"]),
    ],
    targets: [
        // Rules and scheduling. Foundation only, so `swift test` runs without a simulator.
        .target(name: "AgendaCore"),
        .testTarget(name: "AgendaCoreTests", dependencies: ["AgendaCore"]),
    ]
)
