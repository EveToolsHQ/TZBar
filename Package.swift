// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TZMenu",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "TZMenu",
            path: "Sources/TZMenu",
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
