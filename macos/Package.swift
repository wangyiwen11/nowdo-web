// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NowDoDot",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "NowDoDot", targets: ["NowDoDot"])],
    targets: [
        .target(name: "NowDoCore"),
        .executableTarget(name: "NowDoDot", dependencies: ["NowDoCore"]),
        .testTarget(name: "NowDoCoreTests", dependencies: ["NowDoCore"])
    ],
    swiftLanguageModes: [.v5]
)
