// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacOSTiling",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacOSTiling",
            path: "Sources/MacOSTiling",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        )
    ]
)
