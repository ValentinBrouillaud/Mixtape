import FactoryKit
import SwiftUI

/// Reports app publication and the extension's own acknowledgement separately.
struct WidgetDiagnosticsView: View {
    @Injected(\.playerManager) private var player
    @Environment(\.scenePhase) private var scenePhase
    @State private var bridge = WidgetSnapshotBridge.shared
    @State private var receipt: MixtapeWidgetReadReceipt?

    private func text(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "WidgetStatus")
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(text("Data sharing")) {
                    Text(!appCanPublish ? text("Unavailable") :
                         (receipt == nil ? text("Awaiting widget confirmation") : text("Confirmed by widget")))
                }
                LabeledContent(text("App access")) {
                    Text(appCanPublish ? text("Available") : text("Unavailable"))
                }
                LabeledContent(text("Widget data transfer")) {
                    Text(bridge.lastPublishedSharedIdentifier?.hasPrefix("keychain:") == true ? text("Shared keychain") : text("Shared Mixtape group"))
                }
                LabeledContent(text("Shared identifier")) {
                    Text(bridge.lastPublishedSharedIdentifier ?? MixtapeWidgetStorage.resolvedAppGroupIdentifier ?? text("Unavailable"))
                        .font(.caption).multilineTextAlignment(.trailing)
                }
                LabeledContent(text("Last publication")) {
                    if let date = bridge.lastPublishedAt {
                        Text(date, style: .time)
                    } else { Text(text("Not yet published")) }
                }
                LabeledContent(text("Published title")) {
                    Text(bridge.lastPublishedTitle ?? text("No track selected")).lineLimit(2)
                }
                LabeledContent(text("Playlists"), value: "\(bridge.lastPublishedPlaylistCount)")
                LabeledContent(text("Last extension read")) {
                    if let receipt { Text(receipt.readAt, style: .time) }
                    else { Text(text("Not yet confirmed")) }
                }
            } footer: {
                if appCanPublish && bridge.lastPublishedSharedIdentifier?.hasPrefix("keychain:") == true {
                    Text("Widget metadata is saved in the keychain because the file sharing group is unavailable. Sharing is confirmed only after a widget reads it. No audio or login credentials are stored here.", tableName: "WidgetStatus")
                } else if let issue = MixtapeWidgetStorage.environment.issue {
                    switch issue {
                    case .missingExtension:
                        Text("The widget extension is missing. Keep MixtapeWidgets enabled when signing the app.", tableName: "WidgetStatus")
                    case .conflictingIdentifiers, .noCommonMixtapeGroup:
                        Text("The installed signing does not provide a common Mixtape group for the app and its widget. Both bundles must be signed with the same Mixtape App Group. Refreshing cannot grant this access.", tableName: "WidgetStatus")
                    }
                } else if bridge.publicationIssue == .sharedContainerUnavailable {
                    Text("Mixtape cannot share widget data. Signing must allow the same shared group for the app and its extension.", tableName: "WidgetStatus")
                } else if bridge.publicationIssue != nil {
                    Text("Widget data could not be saved. Try refreshing the widgets.", tableName: "WidgetStatus")
                } else {
                    Text("A publication confirms the app saved its data. An extension read confirms a widget accessed it. iOS controls when widgets refresh.", tableName: "WidgetStatus")
                }
            }
            Section {
                Button { refresh() } label: {
                    Label {
                        Text("Refresh widgets", tableName: "WidgetStatus")
                    } icon: { Image(systemName: "arrow.clockwise") }
                }
                ShareLink(item: diagnosticText) {
                    Label {
                        Text("Share widget diagnostic", tableName: "WidgetStatus")
                    } icon: { Image(systemName: "square.and.arrow.up") }
                }
            } footer: {
                Text("After installing, open Mixtape and play a song. In Sideloadly, keep the widget extension enabled.", tableName: "WidgetStatus")
            }
        }
        .navigationTitle(Text("Widgets", tableName: "WidgetStatus"))
        .task {
            refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                if scenePhase == .active { receipt = MixtapeWidgetStorage.lastReceipt() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { receipt = MixtapeWidgetStorage.lastReceipt() }
        }
        .onChange(of: bridge.lastPublishedAt) { _, _ in receipt = MixtapeWidgetStorage.lastReceipt() }
    }

    private func refresh() {
        bridge.updateHistory(ListeningHistoryStore.shared.entries)
        bridge.updatePlaylists(MixtapeQuickPlaylists.shared.playlists)
        bridge.updatePlayback(song: player.currentTrack, isPlaying: player.isPlaying,
            position: player.progress, duration: player.duration)
        receipt = MixtapeWidgetStorage.lastReceipt()
    }

    private var appCanPublish: Bool {
        MixtapeWidgetStorage.containerURL != nil || (bridge.lastPublishedAt != nil && bridge.publicationIssue == nil)
    }

    private var diagnosticText: String {
        let date: (Date?) -> String = { $0.map { ISO8601DateFormatter().string(from: $0) } ?? "none" }
        let info = Bundle.main.infoDictionary ?? [:]
        let environment = MixtapeWidgetStorage.environment
        let groups: (MixtapeWidgetGroupResolver.Profile?) -> String = { profile in
            guard let profile else { return "unknown profile format or missing profile" }
            return profile.groups.isEmpty ? "none" : profile.groups.joined(separator: ", ")
        }
        return [
            "Mixtape widget diagnostic",
            "version: \(info["CFBundleShortVersionString"] ?? "unknown") (\(info["CFBundleVersion"] ?? "unknown"))",
            "app: \(Bundle.main.bundleIdentifier ?? "unknown")",
            "widget: \(environment.widgetIdentifier ?? "missing")",
            "appProfileGroups: \(groups(environment.appProfile))",
            "widgetProfileGroups: \(groups(environment.widgetProfile))",
            "candidateGroups: \(environment.candidates.joined(separator: ", "))",
            "configurationIssue: \(environment.issue?.rawValue ?? "none")",
            "keychainCandidates: \(MixtapeWidgetKeychain.candidates(in: environment).map(\.identifier).joined(separator: ", "))",
            "publishedSharedIdentifier: \(bridge.lastPublishedSharedIdentifier ?? "none")",
            "sharedGroup: \(MixtapeWidgetStorage.resolvedAppGroupIdentifier ?? "unavailable")",
            "publicationIssue: \(bridge.publicationIssue.map { String(describing: $0) } ?? "none")",
            "publicationDetails: \(bridge.publicationDetails ?? "none")",
            "lastPublication: \(date(bridge.lastPublishedAt))",
            "lastExtensionRead: \(date(receipt?.readAt))",
            "extensionSnapshot: \(date(receipt?.snapshotUpdatedAt))",
            "extensionGroup: \(receipt?.appGroupIdentifier ?? "unavailable")"
        ].joined(separator: "\n")
    }
}
