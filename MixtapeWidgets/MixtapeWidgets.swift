import SwiftUI
import Foundation
import WidgetKit

@main
struct MixtapeWidgetBundle: WidgetBundle {
    var body: some Widget {
        MixtapeResumeWidget()
        MixtapeRecentsWidget()
        MixtapeFavoritePlaylistWidget()
    }
}

struct MixtapeTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: MixtapeWidgetSnapshot
    var storageIssue: MixtapeWidgetReadIssue? = nil
}

struct MixtapeTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> MixtapeTimelineEntry {
        MixtapeTimelineEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (MixtapeTimelineEntry) -> Void) {
        let result = MixtapeWidgetStorage.read()
        MixtapeWidgetStorage.acknowledge(result)
        completion(MixtapeTimelineEntry(date: Date(), snapshot: result.snapshot, storageIssue: result.issue))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MixtapeTimelineEntry>) -> Void) {
        let result = MixtapeWidgetStorage.read()
        MixtapeWidgetStorage.acknowledge(result)
        let entry = MixtapeTimelineEntry(date: Date(), snapshot: result.snapshot, storageIssue: result.issue)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60 * 30))))
    }
}

struct MixtapeResumeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MixtapeResume", provider: MixtapeTimelineProvider()) { entry in
            WidgetSurface(appearance: entry.snapshot.appearance) {
                if let issue = entry.storageIssue { WidgetStorageNoticeView(issue: issue) }
                else { ResumeWidgetView(snapshot: entry.snapshot) }
            }
        }
        .configurationDisplayName("Resume")
        .description("Open Mixtape and resume your music.")
        .supportedFamilies([.systemSmall])
    }
}

struct MixtapeRecentsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MixtapeRecents", provider: MixtapeTimelineProvider()) { entry in
            WidgetSurface(appearance: entry.snapshot.appearance) {
                if let issue = entry.storageIssue { WidgetStorageNoticeView(issue: issue) }
                else { RecentsWidgetView(snapshot: entry.snapshot) }
            }
        }
        .configurationDisplayName("Recent Listening")
        .description("Your latest song and four recent favorites, ready to open in Mixtape.")
        .supportedFamilies([.systemMedium])
    }
}

struct MixtapeFavoritePlaylistWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "MixtapeFavoritePlaylist", intent: FavoritePlaylistIntent.self, provider: FavoritePlaylistProvider()) { entry in
            WidgetSurface(appearance: entry.snapshot.appearance) {
                if let issue = entry.storageIssue { WidgetStorageNoticeView(issue: issue) }
                else { FavoritePlaylistWidgetView(playlist: entry.playlist, snapshot: entry.snapshot) }
            }
        }
        .configurationDisplayName("Favorite Playlist")
        .description("Choose a Mixtape playlist to open with one tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
