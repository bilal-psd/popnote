// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Popnote",
    platforms: [.macOS(.v14)],
    targets: [
        // Storage and expiry rules, no UI. Kept separate so it can be unit tested.
        .target(
            name: "PopnoteCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Popnote",
            dependencies: ["PopnoteCore"]
        ),
        .testTarget(
            name: "PopnoteCoreTests",
            dependencies: ["PopnoteCore"]
        ),
    ]
)
