// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RiceStudio",
    platforms: [.macOS(.v14)],
    targets: [
        // Uygulama ve `rice` CLI aynı binary (CLI.isCLI argv'ye bakar)
        .executableTarget(name: "RiceStudio", path: "Sources/RiceStudio")
    ]
)
