import FactoryKit
import SwiftUI

/// Shared song actions: explicit play-next and FIFO additions ahead of the
/// remaining playlist. Adding a song does not interrupt the current track.
struct QueueContextMenuItems: View {
    @Injected(\.playerManager) private var player
    let song: Song

    var body: some View {
        Button { player.insertNextInQueue([song]) } label: {
            Label("Play next", systemImage: "text.insert")
        }
        Button { player.addToQueue([song]) } label: {
            Label("Add to queue", systemImage: "text.badge.plus")
        }
    }
}
