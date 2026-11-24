// swift-tools-version: 6.2
import PackageDescription

// HTTP and AVFoundation decoding tests run on macOS without a simulator,
// signing, audio hardware or an external music-service account.
let package = Package(
    name: "NativeAudioTransport",
    platforms: [.macOS(.v13)],
    products: [.library(name: "NativeAudioTransport", targets: ["NativeAudioTransport"])],
    targets: [
        .target(
            name: "NativeAudioTransport",
            path: "Services",
            sources: [
                "Player/HTTPAudioRangeClient.swift",
                "Player/HTTPAudioResourceLoader.swift",
                "Player/MixtapeHTTPAudioTransfer.swift",
                "API/Models/PlayerResponse.swift",
            ]
        ),
        .testTarget(
            name: "NativeAudioTransportTests",
            dependencies: ["NativeAudioTransport"],
            path: "Tests/NativeAudioTransportTests",
            exclude: ["Fixtures"]
        ),
    ]
)
