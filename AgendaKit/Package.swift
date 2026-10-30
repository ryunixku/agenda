// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AgendaKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "AgendaCore", targets: ["AgendaCore"]),
        .library(name: "AgendaData", targets: ["AgendaData"]),
    ],
    targets: [
        // Rules and scheduling. Foundation only, so `swift test` runs without a simulator.
        .target(name: "AgendaCore"),
        // SwiftData storage synced through iCloud, and the store every surface writes through.
        .target(name: "AgendaData", dependencies: ["AgendaCore"]),
        .testTarget(name: "AgendaCoreTests", dependencies: ["AgendaCore"]),
        .testTarget(name: "AgendaDataTests", dependencies: ["AgendaData"]),
    ]
)
