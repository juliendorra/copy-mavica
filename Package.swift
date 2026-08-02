// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MavicaCopy",
    platforms: [
        .macOS(.v13),
        .iOS(.v17)
    ],
    targets: [
        .target(
            name: "MavicaCore",
            path: "Sources/MavicaCore"
        ),
        .executableTarget(
            name: "MavicaCopy",
            dependencies: ["MavicaCore"],
            path: "Sources/MavicaCopy"
        ),
        // Plain executable check-runner: XCTest is not shipped with the
        // Command Line Tools, so tests run via `swift run MavicaChecks`.
        .executableTarget(
            name: "MavicaChecks",
            dependencies: ["MavicaCore"],
            path: "Checks"
        )
    ]
)
