// swift-tools-version: 6.0
import Foundation
import PackageDescription

var targets: [Target] = [
    .executableTarget(
        name: "SteamPlayMacApp",
        dependencies: ["Sparkle"],
        path: "Sources/SteamPlayMacApp"
    )
]

if FileManager.default.fileExists(atPath: "Tests/SteamPlayMacAppTests") {
    targets.append(.testTarget(
        name: "SteamPlayMacAppTests",
        dependencies: ["SteamPlayMacApp"],
        path: "Tests/SteamPlayMacAppTests"
    ))
}

let package = Package(
    name: "SteamPlayMacApp",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6"),
    ],
    targets: targets
)
