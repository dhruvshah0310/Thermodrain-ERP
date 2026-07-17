// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "JarvisAssistant",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "JarvisAssistant",
            path: "Sources/JarvisAssistant"
        )
    ]
)
