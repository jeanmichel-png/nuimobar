// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NuimoBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "NuimoBar", path: "Sources/NuimoBar")
    ]
)
