// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TZBar",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "TZBar",
            path: "Sources/TZBar",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("MapKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
