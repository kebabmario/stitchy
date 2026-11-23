// swift-tools-version: 6.0
// Stitchy is a native AppKit + SwiftUI app. This package is the project file:
// open `Package.swift` in Xcode, or run `Scripts/build-app.sh` to produce Stitchy.app.
import PackageDescription

let package = Package(
    name: "Stitchy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Stitchy",
            path: "Stitchy",
            exclude: ["Resources"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "StitchyTests",
            dependencies: ["Stitchy"],
            path: "Tests/StitchyTests"
        ),
    ]
)
