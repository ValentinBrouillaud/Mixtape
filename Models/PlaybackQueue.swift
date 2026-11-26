import Foundation

/// One identity per occurrence: adding the same song twice creates two rows.
/// User additions form a FIFO block ahead of the remaining playlist or radio.
nonisolated struct PlaybackQueue<Track: Codable & Sendable>: Codable, Sendable {
    struct Entry: Identifiable, Codable, Sendable {
        let id: UUID
        var track: Track
        var isUserAdded: Bool

        init(track: Track, isUserAdded: Bool = false) {
            id = UUID()
            self.track = track
            self.isUserAdded = isUserAdded
        }
    }

    enum Placement { case next, afterUserAdditions, end }

    private(set) var entries: [Entry] = []
    /// -1 means songs have been queued but playback has not selected one yet.
    private(set) var currentIndex = -1
    var current: Entry? { entries.indices.contains(currentIndex) ? entries[currentIndex] : nil }
    var upcoming: [Entry] { Array(entries.dropFirst(max(0, currentIndex + 1))) }

    mutating func replace(with tracks: [Track], startingAt index: Int = 0) {
        entries = tracks.map { Entry(track: $0) }
        currentIndex = entries.isEmpty ? -1 : min(max(0, index), entries.count - 1)
    }

    @discardableResult mutating func select(_ index: Int) -> Bool {
        guard entries.indices.contains(index) else { return false }
        currentIndex = index
        return true
    }

    mutating func updateCurrent(_ track: Track) {
        guard entries.indices.contains(currentIndex) else { return }
        entries[currentIndex].track = track
    }

    mutating func insert(_ tracks: [Track], placement: Placement) {
        guard !tracks.isEmpty else { return }
        var index = max(0, currentIndex + 1)
        switch placement {
        case .next: break
        case .afterUserAdditions:
            while index < entries.count, entries[index].isUserAdded { index += 1 }
        case .end: index = entries.count
        }
        entries.insert(contentsOf: tracks.map { Entry(track: $0, isUserAdded: true) }, at: index)
    }

    mutating func appendSource(_ tracks: [Track]) {
        entries.append(contentsOf: tracks.map { Entry(track: $0) })
    }

    mutating func remove(ids: Set<UUID>) {
        let selected = current?.id
        entries.removeAll { ids.contains($0.id) && $0.id != selected }
        currentIndex = selected.flatMap { selected in entries.firstIndex { $0.id == selected } } ?? -1
    }

    mutating func clearUpcoming() {
        if let current { entries = [current]; currentIndex = 0 }
        else { entries = []; currentIndex = -1 }
    }

    mutating func moveUpcoming(from offsets: IndexSet, to destination: Int) {
        let start = max(0, currentIndex + 1)
        var tail = upcoming
        let valid = offsets.filter { tail.indices.contains($0) }
        guard !valid.isEmpty, destination >= 0, destination <= tail.count else { return }
        let moved = valid.map { offset -> Entry in
            var entry = tail[offset]
            entry.isUserAdded = true
            return entry
        }
        let selected = Set(valid)
        tail = tail.enumerated().compactMap { selected.contains($0.offset) ? nil : $0.element }
        let insertion = min(tail.count, max(0, destination - valid.filter { $0 < destination }.count))
        tail.insert(contentsOf: moved, at: insertion)
        entries.replaceSubrange(start..<entries.count, with: tail)
    }

    mutating func moveToNext(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }), index > currentIndex else { return }
        var entry = entries.remove(at: index)
        entry.isUserAdded = true
        entries.insert(entry, at: max(0, currentIndex + 1))
    }

    mutating func moveToEnd(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }), index > currentIndex else { return }
        var entry = entries.remove(at: index)
        entry.isUserAdded = true
        entries.append(entry)
    }

    /// Unknown, repeated or omitted IDs never delete or duplicate occurrences.
    mutating func reorderUpcoming(ids: [UUID]) {
        let tail = upcoming
        var seen: Set<UUID> = []
        let reordered = ids.compactMap { id -> Entry? in
            guard seen.insert(id).inserted else { return nil }
            return tail.first { $0.id == id }
        }
        let remaining = tail.filter { !seen.contains($0.id) }
        entries.replaceSubrange(max(0, currentIndex + 1)..<entries.count, with: reordered + remaining)
    }

    /// Shuffle only source occurrences. Explicit additions keep their priority
    /// and order, while Next always follows the actual visible queue.
    mutating func shuffleUpcoming<R: RandomNumberGenerator>(using generator: inout R) {
        let slots = entries.indices.filter { $0 > currentIndex && !entries[$0].isUserAdded }
        var shuffled = slots.map { entries[$0] }
        shuffled.shuffle(using: &generator)
        for (index, entry) in zip(slots, shuffled) { entries[index] = entry }
    }

    /// Discard corrupt identities/indexes instead of restoring ambiguous rows.
    var isValid: Bool {
        Set(entries.map(\.id)).count == entries.count && currentIndex >= -1 && currentIndex < entries.count
    }
}
