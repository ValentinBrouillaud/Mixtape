import AppIntents
import Foundation
import WidgetKit

struct FavoritePlaylistEntity: AppEntity {
    let id: String
    let name: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Playlist" }
    static var defaultQuery: FavoritePlaylistQuery { FavoritePlaylistQuery() }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct FavoritePlaylistQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FavoritePlaylistEntity] {
        let playlists = MixtapeWidgetStorage.load().playlists
        return identifiers.compactMap { id in
            playlists.first { $0.id == id }.map { FavoritePlaylistEntity(id: $0.id, name: $0.title) }
        }
    }

    func suggestedEntities() async throws -> [FavoritePlaylistEntity] {
        MixtapeWidgetStorage.load().playlists.map { FavoritePlaylistEntity(id: $0.id, name: $0.title) }
    }

    func defaultResult() async -> FavoritePlaylistEntity? {
        try? await suggestedEntities().first
    }
}

struct FavoritePlaylistIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Favorite Playlist" }
    static var description: IntentDescription { IntentDescription("Choose the playlist this widget opens.") }
    @Parameter(title: "Playlist") var playlist: FavoritePlaylistEntity?
}

struct FavoritePlaylistEntry: TimelineEntry {
    let date: Date
    let playlist: MixtapeWidgetPlaylist?
    var storageIssue: MixtapeWidgetReadIssue? = nil
    var snapshot: MixtapeWidgetSnapshot = .empty
}

struct FavoritePlaylistProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FavoritePlaylistEntry {
        FavoritePlaylistEntry(date: Date(), playlist: MixtapeWidgetPlaylist(id: UUID().uuidString, title: "Mixtape", songCount: 12))
    }

    func snapshot(for configuration: FavoritePlaylistIntent, in context: Context) async -> FavoritePlaylistEntry {
        makeEntry(configuration)
    }

    func timeline(for configuration: FavoritePlaylistIntent, in context: Context) async -> Timeline<FavoritePlaylistEntry> {
        Timeline(entries: [makeEntry(configuration)], policy: .after(Date().addingTimeInterval(60 * 30)))
    }

    private func makeEntry(_ configuration: FavoritePlaylistIntent) -> FavoritePlaylistEntry {
        let result = MixtapeWidgetStorage.read()
        MixtapeWidgetStorage.acknowledge(result)
        let playlists = result.snapshot.playlists
        let selected: MixtapeWidgetPlaylist?
        if let chosen = configuration.playlist { selected = playlists.first { $0.id == chosen.id } }
        else { selected = playlists.first }
        return FavoritePlaylistEntry(date: Date(), playlist: selected, storageIssue: result.issue, snapshot: result.snapshot)
    }
}
