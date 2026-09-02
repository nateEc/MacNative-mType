// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TypebarServer",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/vapor/vapor.git", from: "4.0.0")],
    targets: [
        .target(
            name: "TypebarServerCore",
            dependencies: [.product(name: "Vapor", package: "vapor")]
        ),
        .executableTarget(name: "TypebarServer", dependencies: ["TypebarServerCore", .product(name: "Vapor", package: "vapor")]),
        .testTarget(
            name: "TypebarServerCoreTests",
            dependencies: ["TypebarServerCore", .product(name: "XCTVapor", package: "vapor")]
        )
    ]
)
