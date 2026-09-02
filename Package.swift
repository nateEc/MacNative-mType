// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Typebar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Typebar", targets: ["Typebar"])],
    targets: [
        .executableTarget(name: "Typebar"),
        .testTarget(name: "TypebarTests", dependencies: ["Typebar"])
    ]
)
