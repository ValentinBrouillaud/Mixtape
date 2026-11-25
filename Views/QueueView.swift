import FactoryKit
import SwiftUI

/// The visible order is the playback order. Each row identifies one occurrence,
/// so duplicate songs can be reordered or removed independently.
struct QueueView: View {
    @Injected(\.playerManager) private var playerManager
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif

    var body: some View {
        VStack(spacing: 0) {
            header
            if playerManager.queueEntries.isEmpty {
                emptyState
            } else {
                queueList
            }
        }
        #if os(macOS)
        .frame(minWidth: 280, maxWidth: 280)
        #endif
        .accessibilityIdentifier(AccessibilityID.Queue.container)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Queue").font(.headline)
            Spacer()
            if !playerManager.upcomingQueueEntries.isEmpty {
                #if os(iOS)
                Button(editMode == .active ? "Done" : "Reorder") {
                    withAnimation { editMode = editMode == .active ? .inactive : .active }
                }
                .font(.subheadline)
                .accessibilityLabel(editMode == .active ? "Finish reordering queue" : "Reorder queue")
                #endif
                Button("Clear") { playerManager.clearQueue() }
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Clear upcoming songs")
                    .accessibilityIdentifier(AccessibilityID.Queue.clearButton)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    private var queueList: some View {
        List {
            if let entry = playerManager.currentQueueEntry {
                Section {
                    QueueEntryRow(entry: entry, isCurrent: true, onPlay: {
                        Task { await playerManager.resume() }
                    })
                    .moveDisabled(true)
                    .deleteDisabled(true)
                } header: {
                    Text("Now playing")
                }
            }
            Section {
                let upcoming = playerManager.upcomingQueueEntries
                ForEach(Array(upcoming.enumerated()), id: \.element.id) { offset, entry in
                    QueueEntryRow(
                        entry: entry,
                        isCurrent: false,
                        onPlay: { Task { await playerManager.playFromQueue(id: entry.id) } },
                        onPlayNext: { playerManager.moveQueueEntryToNext(id: entry.id) },
                        onMoveToEnd: { playerManager.moveQueueEntryToEnd(id: entry.id) },
                        onRemove: { playerManager.removeQueueEntry(id: entry.id) }
                    )
                    .accessibilityIdentifier(AccessibilityID.Queue.row(index: playerManager.currentIndex + offset + 1))
                    .accessibilityAction(named: Text("Play next")) { playerManager.moveQueueEntryToNext(id: entry.id) }
                    .accessibilityAction(named: Text("Move to end")) { playerManager.moveQueueEntryToEnd(id: entry.id) }
                    .accessibilityAction(named: Text("Remove from queue")) { playerManager.removeQueueEntry(id: entry.id) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { playerManager.removeQueueEntry(id: entry.id) } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                    }
                }
                .onMove { offsets, destination in
                    playerManager.moveUpcomingQueue(from: offsets, to: destination)
                }
                .onDelete { offsets in
                    for offset in offsets where upcoming.indices.contains(offset) {
                        playerManager.removeQueueEntry(id: upcoming[offset].id)
                    }
                }
                if upcoming.isEmpty {
                    Text("Nothing queued next")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            } header: {
                Text("Next up")
            } footer: {
                Text("Songs you add to the queue play before the remaining playlist or radio.")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
        .accessibilityIdentifier(AccessibilityID.Queue.scrollView)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Queue", systemImage: "list.bullet")
        } description: {
            Text("Add songs from their menu or start a playlist.")
        }
        .accessibilityIdentifier(AccessibilityID.Queue.emptyState)
    }
}

private struct QueueEntryRow: View {
    let entry: PlaybackQueue<Song>.Entry
    let isCurrent: Bool
    let onPlay: () -> Void
    var onPlayNext: (() -> Void)?
    var onMoveToEnd: (() -> Void)?
    var onRemove: (() -> Void)?

    private var song: Song { entry.track }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPlay) {
                RemoteImage(url: song.thumbnailURL?.cardThumbnailURL, placeholder: {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.quaternary)
                        .overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
                })
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .accessibilityLabel("Play \(song.title)")

            VStack(alignment: .leading, spacing: 3) {
                Button(action: onPlay) {
                    Text(song.title)
                        .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? .red : .primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ArtistLinksView(artists: song.artists)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !isCurrent, entry.isUserAdded {
                    Text("Added by you")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if isCurrent {
                Image(systemName: "waveform")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Now playing")
            } else {
                Menu {
                    if let onPlayNext {
                        Button(action: onPlayNext) { Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                    }
                    if let onMoveToEnd {
                        Button(action: onMoveToEnd) { Label("Move to end", systemImage: "text.append") }
                    }
                    if let onRemove {
                        Button(role: .destructive, action: onRemove) { Label("Remove from queue", systemImage: "minus.circle") }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Queue actions for \(song.title)")
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .listRowBackground(isCurrent ? Color.red.opacity(0.08) : .clear)
    }
}
