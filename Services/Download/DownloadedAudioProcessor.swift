import Accelerate
import AVFoundation
import Foundation

/// Finishes an offline download using decoded audio, not an API/container duration hint.
/// The input is never replaced here: callers publish the verified output atomically.
nonisolated enum DownloadedAudioProcessor {
    static let silenceThreshold: Float = 0.00031623 // About -70 dBFS; retain quiet fades.
    static let minimumTrailingSilence: TimeInterval = 3
    static let endingMargin: TimeInterval = 0.2
    static let durationTolerance: TimeInterval = 0.25

    enum Method: String, Sendable { case unchanged, passthrough, reencoded }

    struct Result: Sendable {
        let url: URL
        let duration: TimeInterval
        let originalDuration: TimeInterval
        let method: Method
    }

    struct Scan: Sendable {
        let frames: AVAudioFramePosition
        let sampleRate: Double
        let channels: AVAudioChannelCount
        let lastSignalFrame: AVAudioFramePosition?

        var duration: TimeInterval { Double(frames) / sampleRate }
        var signalEnd: TimeInterval? { lastSignalFrame.map { Double($0) / sampleRate } }
    }

    enum Failure: LocalizedError {
        case invalidAudio, cannotNormalize
        case emptyAudioFile(String), invalidPCM(String), incompleteRead(AVAudioFramePosition)

        var errorDescription: String? {
            switch self {
            case .invalidAudio, .emptyAudioFile, .invalidPCM, .incompleteRead: "The downloaded file contains no valid decodable audio."
            case .cannotNormalize: "The downloaded audio duration could not be corrected. Please retry the download."
            }
        }
    }

    /// Decode the file's sample frames sequentially. Movie timestamps may
    /// advertise minutes beyond those packets. Never request another block
    /// after the audio reader reaches its end (some codecs throw nilError).
    static func scan(at url: URL) throws -> Scan {
        try Task.checkCancellation()
        guard url.isFileURL else { throw Failure.invalidAudio }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        defer { file.close() }
        let format = file.processingFormat
        guard format.sampleRate.isFinite, (1...384_000).contains(format.sampleRate),
              (1...32).contains(format.channelCount),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_768) else { throw Failure.invalidAudio }
        var frames: AVAudioFramePosition = 0
        var lastSignal: AVAudioFramePosition?
        while file.framePosition < file.length {
            try Task.checkCancellation()
            let remaining = file.length - file.framePosition
            let requested = AVAudioFrameCount(min(remaining, AVAudioFramePosition(buffer.frameCapacity)))
            try file.read(into: buffer, frameCount: requested)
            let count = Int(buffer.frameLength)
            guard count > 0 else { break }
            guard let channels = buffer.floatChannelData else { throw Failure.invalidAudio }
            let (next, overflow) = frames.addingReportingOverflow(AVAudioFramePosition(count))
            guard !overflow else { throw Failure.invalidAudio }
            for channel in 0..<Int(format.channelCount) {
                // Vector operations keep long silence scans cheap and reject
                // non-finite decoded values without a Swift loop per sample.
                var peak: Float = 0
                var sum: Float = 0
                vDSP_maxmgv(channels[channel], 1, &peak, vDSP_Length(count))
                vDSP_sve(channels[channel], 1, &sum, vDSP_Length(count))
                guard peak.isFinite, sum.isFinite else { throw Failure.invalidPCM(url.lastPathComponent) }
                if peak > silenceThreshold {
                    for index in stride(from: count - 1, through: 0, by: -1) {
                        if abs(channels[channel][index]) > silenceThreshold {
                            lastSignal = max(lastSignal ?? 0, frames + AVAudioFramePosition(index) + 1)
                            break
                        }
                    }
                }
            }
            frames = next
        }
        guard frames > 0 else { throw Failure.emptyAudioFile(url.lastPathComponent) }
        return Scan(frames: frames, sampleRate: format.sampleRate, channels: format.channelCount, lastSignalFrame: lastSignal)
    }

    /// Keep everything through the last signal, including gaps and later quiet
    /// passages. Never manufacture an empty song from entirely silent content.
    static func targetFrames(for scan: Scan, reportedDuration: TimeInterval?) -> AVAudioFramePosition? {
        if let last = scan.lastSignalFrame,
           Double(scan.frames - last) / scan.sampleRate >= minimumTrailingSilence {
            return min(scan.frames, last + AVAudioFramePosition(ceil(endingMargin * scan.sampleRate)))
        }
        guard let reportedDuration, reportedDuration.isFinite, reportedDuration > 0,
              abs(reportedDuration - scan.duration) <= 1 else { return scan.frames }
        return nil
    }

    @concurrent
    static func prepare(at url: URL, bitRate: Int? = nil) async throws -> Result {
        try Task.checkCancellation()
        let original = try scan(at: url)
        let asset = AVURLAsset(url: url)
        let reported = try? await asset.load(.duration).seconds
        try Task.checkCancellation()
        guard let frames = targetFrames(for: original, reportedDuration: reported) else {
            return Result(url: url, duration: original.duration, originalDuration: original.duration, method: .unchanged)
        }
        let targetDuration = Double(frames) / original.sampleRate
        let output = url.deletingLastPathComponent().appendingPathComponent("mixtape-normalized-\(UUID().uuidString).m4a")
        var keepOutput = false
        defer { if !keepOutput { try? FileManager.default.removeItem(at: output) } }

        // Preserve the original AAC packets whenever the container can be
        // remuxed correctly. Validate duration after export; stale timing must
        // not let a file with the same blank tail through again.
        if let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough),
           exporter.supportedFileTypes.contains(.m4a) {
            do {
                exporter.timeRange = CMTimeRange(start: .zero,
                    duration: CMTime(seconds: targetDuration, preferredTimescale: 60_000))
                try await exporter.export(to: output, as: .m4a)
                let duration = try await validateOutput(at: output, targetDuration: targetDuration, original: original)
                try Task.checkCancellation()
                keepOutput = true
                return Result(url: output, duration: duration, originalDuration: validDuration(reported) ?? original.duration, method: .passthrough)
            } catch {
                try Task.checkCancellation()
                try? FileManager.default.removeItem(at: output)
            }
        }

        // A fresh AAC timeline handles broken timestamps or unsupported remux
        // inputs. Preserve every decoded frame before the chosen endpoint.
        try writeAAC(from: url, to: output, frames: frames, scan: original, bitRate: bitRate)
        let duration = try await validateOutput(at: output, targetDuration: targetDuration, original: original)
        try Task.checkCancellation()
        keepOutput = true
        return Result(url: output, duration: duration, originalDuration: validDuration(reported) ?? original.duration, method: .reencoded)
    }

    private static func validDuration(_ value: TimeInterval?) -> TimeInterval? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func validateOutput(at url: URL, targetDuration: TimeInterval, original: Scan) async throws -> TimeInterval {
        try Task.checkCancellation()
        let output = try scan(at: url)
        let reported = try await AVURLAsset(url: url).load(.duration).seconds
        let file = try AVAudioFile(forReading: url)
        defer { file.close() }
        let codec = file.fileFormat.streamDescription.pointee.mFormatID
        guard [kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2].contains(codec) else {
            throw Failure.cannotNormalize
        }
        guard reported.isFinite,
              abs(output.duration - targetDuration) <= durationTolerance,
              abs(reported - output.duration) <= durationTolerance else { throw Failure.cannotNormalize }
        if let originalEnd = original.signalEnd {
            guard let outputEnd = output.signalEnd, outputEnd >= originalEnd - 0.1 else { throw Failure.cannotNormalize }
        }
        return output.duration
    }

    private static func writeAAC(from input: URL, to output: URL, frames: AVAudioFramePosition, scan: Scan, bitRate: Int?) throws {
        let reader = try AVAudioFile(forReading: input, commonFormat: .pcmFormatFloat32, interleaved: false)
        defer { reader.close() }
        reader.framePosition = 0
        guard let buffer = AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: 32_768) else { throw Failure.invalidAudio }
        let selectedBitRate = min(512_000, max(32_000, bitRate ?? Int(scan.channels) * 128_000))
        // Explicitly finalize AAC packets and MP4 metadata before validation;
        // an autoreleased writer can otherwise leave a zero-length timeline.
        let writer = try AVAudioFile(forWriting: output, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: scan.sampleRate,
            AVNumberOfChannelsKey: scan.channels,
            AVEncoderBitRateKey: selectedBitRate,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        defer { writer.close() }
        var remaining = frames
        while remaining > 0 {
            try Task.checkCancellation()
            let count = AVAudioFrameCount(min(remaining, AVAudioFramePosition(buffer.frameCapacity)))
            try reader.read(into: buffer, frameCount: count)
            let received = buffer.frameLength
            guard received > 0, received <= count else { throw Failure.incompleteRead(remaining) }
            try writer.write(from: buffer)
            remaining -= AVAudioFramePosition(received)
        }
    }
}
