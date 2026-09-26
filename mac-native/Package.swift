// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DataMoverMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DataMoverMac",
            path: "Sources/DataMoverMac"
        ),
        // Teste deterministe, doar în directoare temporare (niciun volum real).
        .testTarget(
            name: "DataMoverMacTests",
            dependencies: ["DataMoverMac"],
            path: "Tests/DataMoverMacTests"
        )
    ]
)
