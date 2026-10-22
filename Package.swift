// swift-tools-version: 5.9
import PackageDescription

// For IDE navigation and executable builds. scripts/build.sh also creates/signs the .app bundle.
let package = Package(
    name: "Loki",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Loki", targets: ["Loki"])],
    targets: [
        .executableTarget(name: "Loki", path: "native", linkerSettings: [
            .linkedFramework("AppKit"), .linkedFramework("SwiftUI"),
            .linkedFramework("ApplicationServices"), .linkedFramework("Carbon"),
            .linkedFramework("ServiceManagement")
        ])
    ]
)
