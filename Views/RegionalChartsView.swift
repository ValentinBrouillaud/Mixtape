import FactoryKit
import Kingfisher
import SwiftUI

/// Shows up to 50 entries in the official playlist order. Chart title and
/// source stay visible, including when the source ranks music videos.
struct RegionalChartsView: View {
    @Injected(\.ytMusicClient) private var client
    @Injected(\.playerManager) private var player
    @AppStorage("mixtape.charts.country") private var country = "FR"
    @State private var period = RegionalChartDirectory.Period.current
    @State private var choices: [RegionalChartDirectory.Chart] = []
    @State private var playlistID = ""
    @State private var songs: [Song] = []
    @State private var loadingDirectory = false
    @State private var loadingSongs = false
    @State private var error: String?
    @State private var directoryRequest = UUID()
    @State private var songsRequest = UUID()

    private func label(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "RegionalCharts")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker(label("Country"), selection: $country) {
                    ForEach(RegionalChartDirectory.countries.sorted { countryName($0) < countryName($1) }, id: \.self) { code in
                        Text(countryName(code)).tag(code)
                    }
                }
                Picker(label("Period"), selection: $period) {
                    Text(label("Current")).tag(RegionalChartDirectory.Period.current)
                    Text(label("Weekly")).tag(RegionalChartDirectory.Period.weekly)
                    Text(label("Monthly")).tag(RegionalChartDirectory.Period.monthly)
                }.pickerStyle(.segmented)

                if period == .monthly {
                    ContentUnavailableView(label("Monthly chart unavailable"), systemImage: "calendar",
                        description: Text(label("YouTube does not publish an official monthly chart here. No ranking is estimated.")))
                } else {
                    if choices.count > 1 {
                        Picker(label("Official chart"), selection: $playlistID) {
                            ForEach(choices) { chart in Text(chart.title).tag(chart.id) }
                        }
                    } else if let chart = choices.first {
                        Text(chart.title).font(.headline)
                    }
                    if loadingDirectory || loadingSongs {
                        ProgressView(label("Loading chart…")).frame(maxWidth: .infinity).padding()
                    } else if let error {
                        ContentUnavailableView(label("Chart unavailable"), systemImage: "wifi.exclamationmark",
                            description: Text(error))
                        Button(label("Retry")) { Task { await loadDirectory() } }
                    } else if songs.isEmpty {
                        ContentUnavailableView(label("Chart unavailable"), systemImage: "chart.bar",
                            description: Text(label("This session did not return an official playlist for this country and period. You can also consult YouTube Charts.")))
                    } else {
                        HStack {
                            Button { Task { await player.playQueue(songs, startingAt: 0) } } label: {
                                Label(label("Play all"), systemImage: "play.fill")
                            }.buttonStyle(.borderedProminent)
                            Spacer()
                            Text("\(songs.count) / 50").foregroundStyle(.secondary)
                        }
                        LazyVStack(spacing: 12) {
                            ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                                row(song, rank: index + 1)
                            }
                        }
                    }
                    Text(label("Source: YouTube Music. The first 50 available entries retain the source order; availability depends on country and account."))
                        .font(.footnote).foregroundStyle(.secondary)
                    Link(label("Open official YouTube Charts"), destination: officialURL)
                }
            }.padding()
        }
        .mixtapeScrollAbovePlayer()
        .mixtapeScreenStyle()
        .navigationTitle(label("Top 50 by country"))
        .task(id: "\(country):\(period.rawValue)") { await loadDirectory() }
        .task(id: playlistID) { await loadSongs() }
    }

    private func countryName(_ code: String) -> String {
        code == "ZZ" ? label("Worldwide") : Locale.current.localizedString(forRegionCode: code) ?? code
    }

    private var officialURL: URL {
        let region = country == "ZZ" ? "global" : country.lowercased()
        return URL(string: "https://charts.youtube.com/charts/TopSongs/\(region)/weekly")!
    }

    private func row(_ song: Song, rank: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)").monospacedDigit().foregroundStyle(.secondary).frame(width: 25)
            Button { Task { await player.playQueue(songs, startingAt: rank - 1) } } label: {
                KFImage(song.thumbnailURL).resizable().scaledToFill()
                    .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain).accessibilityLabel(song.title)
            VStack(alignment: .leading, spacing: 4) {
                Button(song.title) { Task { await player.playQueue(songs, startingAt: rank - 1) } }
                    .buttonStyle(.plain).font(.subheadline.weight(.medium)).lineLimit(2)
                ArtistLinksView(artists: song.artists).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Menu {
                Button { player.insertNextInQueue([song]) } label: { Label(label("Play next"), systemImage: "text.insert") }
                Button { player.addToQueue([song]) } label: { Label(label("Add to queue"), systemImage: "text.badge.plus") }
                ArtistContextMenuItems(artists: song.artists)
                MixtapeQuickAddMenu(song: song)
            } label: { Image(systemName: "ellipsis").frame(width: 30, height: 40) }
                .accessibilityLabel(label("Song actions"))
        }
    }

    private func loadDirectory() async {
        let token = UUID()
        directoryRequest = token
        songsRequest = UUID()
        choices = []; songs = []; playlistID = ""; error = nil
        loadingSongs = false
        loadingDirectory = period != .monthly
        guard period != .monthly else { return }
        let selectedCountry = country
        let selectedPeriod = period
        do {
            let directory = try await client.getRegionalCharts(country: selectedCountry)
            guard directoryRequest == token, !Task.isCancelled else { return }
            choices = directory.choices(for: selectedPeriod)
            playlistID = choices.first?.id ?? ""
        } catch {
            guard directoryRequest == token, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
        if directoryRequest == token { loadingDirectory = false }
    }

    private func loadSongs() async {
        let id = playlistID
        guard !id.isEmpty else { return }
        let token = UUID()
        songsRequest = token
        loadingSongs = true; songs = []; error = nil
        do {
            let detail = try await client.getPlaylist(id: id)
            guard songsRequest == token, playlistID == id, !Task.isCancelled else { return }
            songs = Array(detail.tracks.prefix(50))
        } catch {
            guard songsRequest == token, playlistID == id, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
        if songsRequest == token { loadingSongs = false }
    }
}
