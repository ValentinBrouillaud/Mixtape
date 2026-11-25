import SwiftUI

extension EnvironmentValues {
    @Entry var openArtist: (@MainActor (Artist) -> Void)? = nil
}

/// Artist credits remain separate controls from the song's playback button.
/// Missing or synthetic IDs are displayed as text and never used for browsing.
struct ArtistLinksView: View {
    let artists: [Artist]
    var onNavigate: (() -> Void)? = nil

    @Environment(\.openArtist) private var openArtist

    var body: some View {
        HStack(spacing: 0) {
            if artists.isEmpty {
                Text("Unknown Artist")
            } else {
                ForEach(Array(artists.enumerated()), id: \.offset) { index, artist in
                    if index > 0 { Text(", ") }
                    if artist.hasNavigableBrowseID, let openArtist {
                        Button {
                            onNavigate?()
                            openArtist(artist)
                        } label: {
                            Text(artist.name)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Open artist")
                    } else {
                        Text(artist.name)
                            .lineLimit(1)
                    }
                }
            }
        }
        .lineLimit(1)
    }
}

/// The same validated destinations are available from song context menus.
struct ArtistContextMenuItems: View {
    let artists: [Artist]
    var onNavigate: (() -> Void)? = nil

    @Environment(\.openArtist) private var openArtist

    private var navigableArtists: [Artist] {
        var seen = Set<String>()
        return artists.filter { $0.hasNavigableBrowseID && seen.insert($0.id).inserted }
    }

    var body: some View {
        if let openArtist {
            let destinations = navigableArtists
            if destinations.count == 1, let artist = destinations.first {
                Button {
                    onNavigate?()
                    openArtist(artist)
                } label: {
                    Label("Go to Artist", systemImage: "person")
                }
            } else if !destinations.isEmpty {
                Menu {
                    ForEach(destinations) { artist in
                        Button(artist.name) {
                            onNavigate?()
                            openArtist(artist)
                        }
                    }
                } label: {
                    Label("Go to Artist", systemImage: "person")
                }
            }
        }
    }
}
