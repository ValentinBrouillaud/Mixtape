//
//  ExploreContentView.swift
//  Mixtape
//
//  Content view for Explore tab, used with DiscoverCoordinator.
//  This view does not include NavigationStack - that's provided by the coordinator.
//

import SwiftUI

struct DiscoveryContentView: View {
    @Bindable var viewModel: DiscoveryViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                NavigationLink {
                    RegionalChartsView()
                } label: {
                    HStack {
                        Image(systemName: "chart.bar.xaxis").font(.title2).foregroundStyle(MixtapePalette.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Top 50 by country", tableName: "RegionalCharts").font(.headline)
                            Text("Current and weekly YouTube charts", tableName: "RegionalCharts")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }.padding().mixtapeCard()
                }.buttonStyle(.plain).padding(.horizontal)
                ForEach(viewModel.sections) { section in
                    sectionView(section)
                }
            }
            .padding(.vertical, 16)
            .scrollClipDisabled()
        }
        .mixtapeScrollAbovePlayer()
        .mixtapeScreenStyle()
        .loading(viewModel.loadingState) {
            await viewModel.load()
        }
    #if os(iOS)
        .inlineLargeTitle("Discovery") {
            Button {
                self.viewModel.didRequestSettings()
            } label: {
                UserProfileView(imageSize: 40)
            }
        }
    #else
        .navigationTitle("Discovery")
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
            .if(!playlist.isMoodOrGenreCategory) { view in
                view.hoverPlay {
                    Task { await self.viewModel.playPlaylist(playlist) }
                }
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
        DiscoveryContentView(viewModel: DiscoveryViewModel())
    }
}
