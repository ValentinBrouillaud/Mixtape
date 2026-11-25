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
            path: ".",
            sources: [
                "Services/Player/HTTPAudioRangeClient.swift",
                "Services/Player/HTTPAudioResourceLoader.swift",
                "Services/Player/MixtapeHTTPAudioTransfer.swift",
                "Services/API/Models/PlayerResponse.swift",
                "Services/Charts/RegionalChartDirectory.swift",
                "Services/History/ListeningHistoryPolicy.swift",
                "Services/History/HistoryThumbnail.swift",
                "Models/PlaybackQueue.swift",
            ]
        ),
        .testTarget(
            name: "NativeAudioTransportTests",
            dependencies: ["NativeAudioTransport"],
            path: "Tests/NativeAudioTransportTests",
            exclude: ["Fixtures"]
        ),
        .target(name: "ArtistNavigation", path: "Models/YTMusic", sources: ["Artist.swift"]),
        .testTarget(name: "ArtistNavigationTests", dependencies: ["ArtistNavigation"], path: "Tests/ArtistNavigationTests"),
        .target(name: "SharedWidgetModel", path: "SharedWidgets"),
        .testTarget(name: "WidgetSnapshotTests", dependencies: ["SharedWidgetModel"], path: "Tests/WidgetSnapshotTests"),
    ]
)
