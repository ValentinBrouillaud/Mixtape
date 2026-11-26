import AppIntents
import Foundation

/// AudioPlaybackIntent is executed by iOS in the containing app's process.
/// Both targets include its declaration so the widget can reference the action.
struct MixtapeWidgetPlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource { .init("Play or pause Mixtape", table: "MixtapeTheme") }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Play") var shouldPlay: Bool
    @Parameter(title: "Track") var videoID: String?
    @Parameter(title: "Playlist") var playlistID: String?

    init() { shouldPlay = true }
    init(shouldPlay: Bool, videoID: String?, playlistID: String? = nil) {
        self.shouldPlay = shouldPlay
        self.videoID = videoID
        self.playlistID = playlistID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if MIXTAPE_HOST_APP
        try await MixtapeWidgetPlaybackHost.perform(shouldPlay: shouldPlay, videoID: videoID, playlistID: playlistID)
        #else
        try requireHostProcess()
        #endif
        return .result()
    }

    private func requireHostProcess() throws {
        throw HostRequired()
    }

    private struct HostRequired: LocalizedError {
        var errorDescription: String? {
            String(localized: "Open Mixtape once to enable its playback controls.", table: "MixtapeTheme")
        }
    }
}
