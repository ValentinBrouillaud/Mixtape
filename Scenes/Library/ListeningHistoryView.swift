import FactoryKit
import SwiftUI

/// A metadata-only history. Tapping Play uses the normal player and never starts a download.
struct ListeningHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = ListeningHistoryStore.shared
    @State private var showClearConfirmation = false

    var body: some View {
        Group {
            if store.entries.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("No listening history yet", tableName: "ListeningHistory")
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                } description: {
                    Text("Songs appear here after you listen for a few seconds.", tableName: "ListeningHistory")
                }
            } else {
                List {
                    Section {
                        ForEach(store.entries) { entry in
                            historyRow(entry)
                                .contextMenu {
                                    Button { play(entry) } label: {
                                        Label {
                                            Text("Play", tableName: "ListeningHistory")
                                        } icon: { Image(systemName: "play.fill") }
                                    }
                                    QueueContextMenuItems(song: entry.playbackSong)
                                    ArtistContextMenuItems(artists: entry.playbackSong.artists, onNavigate: { dismiss() })
                                    Button(role: .destructive) { store.remove(videoId: entry.videoId) } label: {
                                        Label {
                                            Text("Remove from history", tableName: "ListeningHistory")
                                        } icon: { Image(systemName: "clock.badge.xmark") }
                                    }
                                }
                        }
                    } header: {
                        Text("Last 100 songs", tableName: "ListeningHistory")
                    } footer: {
                        Text("Your history is saved on this device. Songs are not downloaded.", tableName: "ListeningHistory")
                    }
                }
                .listStyle(.plain)
                .mixtapeScrollAbovePlayer()
            }
        }
        .mixtapeScreenStyle()
        .navigationTitle(Text("Listening History", tableName: "ListeningHistory"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Text("Close", tableName: "ListeningHistory") }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) { showClearConfirmation = true } label: {
                    Label {
                        Text("Clear history", tableName: "ListeningHistory")
                    } icon: { Image(systemName: "trash") }
                }
                .disabled(store.entries.isEmpty)
            }
        }
        .alert(Text("Clear listening history?", tableName: "ListeningHistory"), isPresented: $showClearConfirmation) {
            Button(role: .destructive) { store.clear() } label: {
                Text("Clear history", tableName: "ListeningHistory")
            }
            Button(role: .cancel) {} label: { Text("Cancel", tableName: "ListeningHistory") }
        } message: {
            Text("This removes the local list. Your library and downloaded songs are kept.", tableName: "ListeningHistory")
        }
    }

    private func historyRow(_ entry: ListeningHistoryEntry) -> some View {
        HStack(spacing: 12) {
            Button { play(entry) } label: {
                HistoryArtworkView(videoId: entry.videoId)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Play", tableName: "ListeningHistory") + Text(" ") + Text(entry.title))

            VStack(alignment: .leading, spacing: 4) {
                Button { play(entry) } label: {
                    Text(entry.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                ArtistLinksView(artists: entry.playbackSong.artists, onNavigate: { dismiss() })
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button { play(entry) } label: { Image(systemName: "play.circle") }
                .buttonStyle(.plain)
                .font(.title2)
                .accessibilityLabel(Text("Play", tableName: "ListeningHistory") + Text(" ") + Text(entry.title))
        }
        .padding(.vertical, 4)
    }

    private func play(_ entry: ListeningHistoryEntry) {
        Task { await Container.shared.playerManager().play(song: entry.playbackSong) }
    }
}
