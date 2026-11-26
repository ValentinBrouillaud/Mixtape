import SwiftUI

// MARK: - PlayerBarAppearance

/// Shared observable for views to communicate color scheme to the PlayerBar.
/// Injected via `.environment()` at the app level.
@Observable @MainActor
final class PlayerBarAppearance {
    /// When set, the PlayerBar uses this instead of the system color scheme.
    var colorSchemeOverride: ColorScheme?
}

// MARK: - PlayerBar (iOS)

#if os(iOS)
struct PlayerBar: View {
    @Bindable var viewModel: PlayerViewModel
    var actualColorScheme: ColorScheme = .dark
    @Binding var showFullscreenPlayer: Bool
    @Environment(PlayerBarAppearance.self) private var appearance
    @State private var showErrorDetails = false

    private var effectiveColorScheme: ColorScheme {
        appearance.colorSchemeOverride ?? actualColorScheme
    }

    private var primaryTextColor: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6)
    }

    private var progressFraction: CGFloat {
        let duration = viewModel.duration
        let progress = viewModel.progress
        guard duration.isFinite, duration > 0, progress.isFinite else { return 0 }
        return CGFloat(min(1, max(0, progress / duration)))
    }

    var body: some View {
        MixtapeMiniPlayerLayout(
            title: viewModel.currentTrack?.title ?? "Not Playing",
            artist: viewModel.currentTrack?.artistsDisplay ?? "",
            isPlaying: viewModel.isPlaying,
            fraction: Double(progressFraction),
            onOpen: { showFullscreenPlayer = true },
            onPlayPause: { viewModel.playPause() },
            onNext: { viewModel.next() },
            onError: viewModel.playbackError == nil ? nil : { showErrorDetails = true },
            onOpenWeb: viewModel.currentPlayerType == .webView ? { viewModel.revealWebPlayer() } : nil
        ) {
            RemoteImage(url: viewModel.currentTrack?.thumbnailURL?.cardThumbnailURL) {
                Rectangle().fill(.quaternary)
                    .overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
            }
            .aspectRatio(contentMode: .fill)
        }
        .sheet(isPresented: $showErrorDetails) {
            NavigationStack {
                ScrollView {
                    Text(viewModel.playbackError ?? "Aucune erreur audio actuelle")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("Diagnostic audio")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") { showErrorDetails = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        ShareLink(item: viewModel.playbackError ?? "Aucune erreur audio") {
                            Label("Partager", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }
}


#endif
