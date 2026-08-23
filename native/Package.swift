// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LanisKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "LanisKit", targets: ["LanisKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "LanisKit",
            dependencies: ["SwiftSoup"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LanisKitTests",
            dependencies: ["LanisKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
