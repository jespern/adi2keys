// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "adi2keys",
    platforms: [.macOS(.v27)],
    targets: [
        .target(name: "ADI2Protocol"),
        .executableTarget(name: "adi2keys", dependencies: ["ADI2Protocol"]),
        .testTarget(name: "ADI2ProtocolTests", dependencies: ["ADI2Protocol"]),
    ]
)
