// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DSHChat",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "DSHChat", targets: ["DSHChat"])],
    dependencies: [.package(path: "../dsh-swift")],
    targets: [
        .executableTarget(
            name: "DSHChat",
            dependencies: [
                .product(name: "DSHKit", package: "dsh-swift"),
                .product(name: "DSHProtocol", package: "dsh-swift"),
                .product(name: "DSHSession", package: "dsh-swift"),
            ]
        ),
        .testTarget(name: "DSHChatTests", dependencies: ["DSHChat"]),
    ],
    swiftLanguageModes: [.v5]
)
