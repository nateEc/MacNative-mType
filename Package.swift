// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Typebar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Typebar", targets: ["Typebar"])],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.14.1")
    ],
    targets: [
        .executableTarget(name: "Typebar", dependencies: ["SwiftSoup"]),
        .testTarget(name: "TypebarTests", dependencies: ["Typebar"])
    ]
)
