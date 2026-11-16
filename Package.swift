// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SevenZipGUI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SevenZipGUI", targets: ["SevenZipGUI"])
    ],
    targets: [
        .executableTarget(
            name: "SevenZipGUI",
            path: "Sources/SevenZipGUI",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
