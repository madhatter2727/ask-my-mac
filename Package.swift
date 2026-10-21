// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AskMyMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AskMyMac", targets: ["AskMyMac"])
    ],
    targets: [
        .executableTarget(
            name: "AskMyMac",
            path: "Sources/AskMyMac"
        )
    ]
)
