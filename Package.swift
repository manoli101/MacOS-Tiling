// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tyler",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Tyler",
            path: "Sources/MacOSTiling",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        )
    ]
)
