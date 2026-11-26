//
//  HomeContentView.swift
//  Mixtape
//
//  Content view for Home tab, used with HomeCoordinator.
//  This view does not include NavigationStack - that's provided by the coordinator.
//

import SwiftUI

/// Home content view displaying personalized content sections.
/// Used by HomeCoordinator - navigation is handled via NavigationLink(value:).
struct HomeContentView: View {
    @Bindable var viewModel: HomeViewModel
    @State private var history = ListeningHistoryStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if !history.entries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recently played", tableName: "MixtapeTheme")
                            .font(.system(size: 23, weight: .bold))
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(history.entries.prefix(6)) { entry in
                                MixtapeRecentTile(title: entry.title, onPlay: {
                                    Task { await viewModel.playerManager.play(song: entry.playbackSong) }
                                }) {
                                    HistoryArtworkView(videoId: entry.videoId, size: 52)
                                }
                            }
                        }
                    }.padding(.horizontal, 16)
                }
                ForEach(self.viewModel.sections) { section in
                    self.sectionView(section)
                }

                if self.viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 16)
            .scrollClipDisabled()
        }
        .mixtapeScrollAbovePlayer()
        .mixtapeScreenStyle()
        .onScrollTargetVisibilityChange(idType: HomeSection.ID.self, threshold: 0.2) { visibleIDs in
            self.viewModel.loadMoreIfNeeded(visibleSectionIDs: Set(visibleIDs))
        }
        .loading(viewModel.loadingState) {
            await viewModel.load()
        }
    #if os(iOS)
        .inlineLargeTitle("Home") {
            Button {
                self.viewModel.didRequestSettings()
            } label: {
                UserProfileView(imageSize: 40)
            }
        }
    #else
        .navigationTitle("Home")
    #endif
        .refreshable {
            viewModel.refresh()
        }
    }

    private func sectionView(_ section: HomeSection) -> some View {
        SectionGroup(
            section: section,
            onNavigate: { self.viewModel.didSelectSection(section) }
        ) { item in
            self.itemCard(item: item)
        }
    }

    @ViewBuilder
    private func itemCard(item: HomeSectionItem) -> some View {
        switch item {
        case let .song(song):
            SongCard(song: song) {
                Task { await viewModel.playerManager.playWithRadio(song: song) }
            }
        case let .playlist(playlist):
            Button {
                self.viewModel.didSelectPlaylist(playlist)
            } label: {
                PlaylistCard(playlist: playlist)
            }
            .buttonStyle(.interactiveCard)
            .hoverPlay {
                Task { await self.viewModel.playPlaylist(playlist) }
            }
        case let .album(album):
            Button {
                self.viewModel.didSelectAlbum(album)
            } label: {
                AlbumCard(album: album)
            }
            .buttonStyle(.interactiveCard)
            .hoverPlay {
                Task { await self.viewModel.playAlbum(album) }
            }
        case let .artist(artist):
            Button {
                self.viewModel.didSelectArtist(artist)
            } label: {
                ArtistCard(artist: artist)
            }
            .buttonStyle(.interactiveCard)
        }
    }
}

#Preview {
    NavigationStack {
        HomeContentView(viewModel: HomeViewModel())
    }
}
