import Foundation

/// A sampled position, not a running timer in either process. WidgetKit can
/// animate the corresponding date interval while the app is in the background.
nonisolated struct MixtapeWidgetPlayback: Codable, Equatable, Sendable {
    let videoID: String
    let position: TimeInterval
    let duration: TimeInterval?
    let sampledAt: Date
    let isAdvancing: Bool

    init(videoID: String, position: TimeInterval, duration: TimeInterval?, sampledAt: Date, isAdvancing: Bool) {
        self.videoID = videoID
        let validDuration = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.duration = validDuration
        let finitePosition = position.isFinite ? max(0, position) : 0
        self.position = validDuration.map { min(finitePosition, $0) } ?? finitePosition
        self.sampledAt = sampledAt.timeIntervalSinceReferenceDate.isFinite ? sampledAt : Date(timeIntervalSince1970: 0)
        self.isAdvancing = isAdvancing
    }

    func position(at date: Date) -> TimeInterval {
        let delta = date.timeIntervalSince(sampledAt)
        let elapsed = isAdvancing && delta.isFinite ? max(0, delta) : 0
        let value = position + elapsed
        return duration.map { min(value, $0) } ?? value
    }

    func fraction(at date: Date) -> Double {
        guard let duration, duration.isFinite, duration > 0 else { return 0 }
        return min(1, max(0, position(at: date) / duration))
    }

    var timerInterval: ClosedRange<Date>? {
        guard isAdvancing, let duration, duration.isFinite, duration > 0 else { return nil }
        let start = sampledAt.addingTimeInterval(-position)
        return start...start.addingTimeInterval(duration)
    }

    func needsPublication(after previous: Self?) -> Bool {
        guard let previous else { return true }
        if videoID != previous.videoID || isAdvancing != previous.isAdvancing { return true }
        if duration != previous.duration { return true }
        if sampledAt < previous.sampledAt { return true }
        return abs(position - previous.position(at: sampledAt)) > 1.5
    }
}

nonisolated enum MixtapeWidgetPlaybackAction: String, Codable, Sendable {
    case play, pause
    func shouldChange(isPlaying: Bool) -> Bool { self == .play ? !isPlaying : isPlaying }
}
