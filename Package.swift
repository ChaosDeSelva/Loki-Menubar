// swift-tools-version: 5.9
import PackageDescription

// For IDE navigation and executable builds. scripts/build.sh also creates/signs the .app bundle.
let package = Package(
    name: "Loki",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Loki", targets: ["Loki"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .executableTarget(name: "Loki", dependencies: [.product(name: "Sparkle", package: "Sparkle")], path: "native", linkerSettings: [
            .linkedFramework("AppKit"), .linkedFramework("SwiftUI"),
            .linkedFramework("ApplicationServices"), .linkedFramework("Carbon"),
            .linkedFramework("ServiceManagement")
        ])
    ]
)
