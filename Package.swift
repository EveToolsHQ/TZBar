// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TZMenu",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TZMenu",
            path: "Sources/TZMenu",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("MapKit"),
            ]
        ),
    ]
)
