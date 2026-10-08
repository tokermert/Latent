// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LatentCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "LatentCore", targets: ["LatentCore"])],
    targets: [
        .target(name: "LatentCore"),
        .executableTarget(name: "LatentCoreChecks", dependencies: ["LatentCore"], path: "Checks"),
        .testTarget(name: "LatentCoreTests", dependencies: ["LatentCore"])
    ]
)
