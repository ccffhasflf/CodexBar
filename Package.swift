// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexBarLite",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CodexBarLite", targets: ["CodexBarLite"])],
    targets: [
        .target(name: "CodexBarLiteCore"),
        .executableTarget(name: "CodexBarLite", dependencies: ["CodexBarLiteCore"]),
        .testTarget(name: "CodexBarLiteTests", dependencies: ["CodexBarLiteCore", "CodexBarLite"]),
    ])
