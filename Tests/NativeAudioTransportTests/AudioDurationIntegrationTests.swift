import AVFoundation
import Foundation
import Testing
@testable import NativeAudioTransport

extension NativeRangeIntegrationTests {
    @Test @MainActor func automaticCleanupRemovesTwoSilentMinutesAndPreservesQuietCodaAndGaps() async throws {
        let root = try DurationFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try DurationFixture.audio(in: root, segments: [(1, 0), (2, 0.25), (4, 0), (1, 0.001), (120, 0)])
        let originalBytes = try Data(contentsOf: source)
        let result = try await DownloadedAudioProcessor.prepare(at: source, bitRate: 128_000)
        #expect(result.method != .unchanged)
        #expect(abs(result.duration - 8.2) < 0.25)
        #expect(try DurationFixture.rms(result.url, at: 0.2) < 0.00001)
        #expect(try DurationFixture.rms(result.url, at: 2) > 0.1)
        #expect(try DurationFixture.rms(result.url, at: 5) < 0.00001)
        #expect(try DurationFixture.rms(result.url, at: 7.5) > 0.0002)
        #expect(try Data(contentsOf: source) == originalBytes)
        let reported = try await AVURLAsset(url: result.url).load(.duration).seconds
        #expect(abs(reported - result.duration) < 0.25)
    }

    @Test @MainActor func normalDownloadKeepsItsOriginalAACBytes() async throws {
        let root = try DurationFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try DurationFixture.audio(in: root, segments: [(4, 0.25), (0.5, 0)])
        let original = try Data(contentsOf: source)
        let result = try await DownloadedAudioProcessor.prepare(at: source)
        #expect(result.method == .unchanged)
        #expect(result.url == source)
        #expect(abs(result.duration - 4.5) < 0.1)
        #expect(try Data(contentsOf: source) == original)
    }

    @Test @MainActor func completelySilentAudioIsNotReplacedWithAnEmptyFile() async throws {
        let root = try DurationFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try DurationFixture.audio(in: root, segments: [(4, 0)])
        let result = try await DownloadedAudioProcessor.prepare(at: source)
        #expect(result.method == .unchanged)
        #expect(result.duration > 3.9)
    }

    @Test @MainActor func unsupportedPassthroughFallsBackToVerifiedAACEncoding() async throws {
        let root = try DurationFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try DurationFixture.audio(in: root, segments: [(2, 0.25), (6, 0)], pcm: true)
        let result = try await DownloadedAudioProcessor.prepare(at: source, bitRate: 64_000)
        #expect(result.method == .reencoded)
        #expect(abs(result.duration - 2.2) < 0.25)
        let file = try AVAudioFile(forReading: result.url)
        #expect(file.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatMPEG4AAC)
        #expect(try DurationFixture.rms(result.url, at: 1) > 0.1)
    }

    @Test @MainActor func misleadingMovieHeadersDoNotOverrideDecodedAudioDuration() async throws {
        let root = try DurationFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try DurationFixture.audio(in: root, segments: [(4, 0.25)])
        try DurationFixture.extendContainerTiming(source, to: 300)
        let reported = try await AVURLAsset(url: source).load(.duration).seconds
        let result = try await DownloadedAudioProcessor.prepare(at: source)
        // AVFoundation may already ignore inconsistent headers. If it exposes
        // their long duration, the processor must rebuild the timeline.
        if reported > 30 { #expect(result.method != .unchanged) }
        #expect(result.duration > 3.8 && result.duration < 4.5)
        #expect(try DurationFixture.rms(result.url, at: 3) > 0.1)
    }

    @Test @MainActor func cancelledCleanupLeavesTheOriginalFileAndNoIntermediateOutput() async throws {
        let root = try DurationFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try DurationFixture.audio(in: root, segments: [(2, 0.25), (10, 0)])
        let original = try Data(contentsOf: source)
        let task = Task { try await DownloadedAudioProcessor.prepare(at: source) }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("A cancelled cleanup must not return a publishable file")
        } catch { #expect(error is CancellationError) }
        #expect(try Data(contentsOf: source) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == [source.lastPathComponent])
    }

    @Test @MainActor func corruptAudioFailsWithoutReplacingTheInput() async throws {
        let root = try DurationFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("input.m4a")
        let bytes = Data("not an audio file".utf8)
        try bytes.write(to: source)
        do {
            _ = try await DownloadedAudioProcessor.prepare(at: source)
            Issue.record("Corrupt media must not be published")
        } catch { }
        #expect(try Data(contentsOf: source) == bytes)
    }

    @Test @MainActor func rangeDownloadedAudioIsNormalizedBeforeOfflinePublication() async throws {
        let root = try DurationFixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try DurationFixture.audio(in: root, segments: [(3, 0.25), (15, 0)])
        let server = try AudioHTTPFixture(mediaURL: source)
        defer { server.stop() }
        let transferred = try await MixtapeHTTPAudioTransfer.fetch(
            url: server.url("range"), expectedBytes: 0, userAgent: "MixtapeDurationTests", progress: { _ in }
        )
        defer { try? FileManager.default.removeItem(at: transferred) }
        let result = try await DownloadedAudioProcessor.prepare(at: transferred)
        defer { if result.url != transferred { try? FileManager.default.removeItem(at: result.url) } }
        #expect(result.method != .unchanged)
        #expect(abs(result.duration - 3.2) < 0.25)
        #expect(try DurationFixture.rms(result.url, at: 2) > 0.1)
    }
}

@MainActor
private enum DurationFixture {
    static let rate = 44_100.0
    enum Failure: Error { case allocation, malformedFixture }

    static func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mixtape-duration-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func audio(in root: URL, segments: [(Double, Float)], pcm: Bool = false) throws -> URL {
        let url = root.appendingPathComponent(pcm ? "input.wav" : "mixtape-test-tone-\(UUID().uuidString).m4a")
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192),
              let samples = buffer.floatChannelData?[0] else { throw Failure.allocation }
        let settings: [String: Any] = pcm ? [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
        ] : [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000,
        ]
        do {
            let writer = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            var position = 0
            for (seconds, amplitude) in segments {
                var remaining = Int(seconds * rate)
                while remaining > 0 {
                    let count = min(remaining, Int(buffer.frameCapacity))
                    buffer.frameLength = AVAudioFrameCount(count)
                    if amplitude == 0 { samples.update(repeating: 0, count: count) }
                    else {
                        for index in 0..<count {
                            samples[index] = amplitude * Float(sin(2 * .pi * 440 * Double(position + index) / rate))
                        }
                    }
                    try writer.write(from: buffer)
                    position += count
                    remaining -= count
                }
            }
        }
        return url
    }

    static func rms(_ url: URL, at seconds: Double) throws -> Double {
        let reader = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        reader.framePosition = AVAudioFramePosition(seconds * reader.processingFormat.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: 4096) else { throw Failure.allocation }
        try reader.read(into: buffer)
        guard buffer.frameLength > 0, let values = buffer.floatChannelData?[0] else { throw Failure.allocation }
        var sum = 0.0
        for index in 0..<Int(buffer.frameLength) { sum += Double(values[index]) * Double(values[index]) }
        return sqrt(sum / Double(buffer.frameLength))
    }

    /// Corrupt movie/track/edit durations without changing AAC packet contents.
    /// Layout follows Apple's QuickTime mvhd/tkhd/elst field definitions.
    static func extendContainerTiming(_ url: URL, to seconds: Double) throws {
        var bytes = [UInt8](try Data(contentsOf: url))
        func integer(_ offset: Int, width: Int = 4) throws -> UInt64 {
            guard offset >= 0, offset + width <= bytes.count else { throw Failure.malformedFixture }
            return bytes[offset..<(offset + width)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        }
        var atoms: [(String, Int)] = []
        func walk(_ start: Int, _ end: Int) throws {
            var offset = start
            while offset + 8 <= end {
                let shortLength = Int(try integer(offset))
                let headerSize = shortLength == 1 ? 16 : 8
                let length = shortLength == 1 ? Int(try integer(offset + 8, width: 8)) : (shortLength == 0 ? end - offset : shortLength)
                guard length >= headerSize, offset + length <= end else { throw Failure.malformedFixture }
                let kind = String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii) ?? ""
                atoms.append((kind, offset + headerSize))
                if ["moov", "trak", "edts"].contains(kind) { try walk(offset + headerSize, offset + length) }
                offset += length
            }
        }
        try walk(0, bytes.count)
        let movie = try #require(atoms.first { $0.0 == "mvhd" }?.1)
        let scale = try integer(movie + (bytes[movie] == 1 ? 20 : 12))
        guard scale > 0 else { throw Failure.malformedFixture }
        let duration = UInt64(seconds * Double(scale))
        for (kind, body) in atoms {
            guard ["mvhd", "tkhd", "elst"].contains(kind), body < bytes.count else { continue }
            let version1 = bytes[body] == 1
            let field: Int
            switch kind {
            case "mvhd": field = body + (version1 ? 24 : 16)
            case "tkhd": field = body + (version1 ? 28 : 20)
            case "elst":
                guard try integer(body + 4) > 0 else { continue }
                field = body + 8
            default: continue
            }
            let width = version1 ? 8 : 4
            guard field + width <= bytes.count else { throw Failure.malformedFixture }
            for index in 0..<width { bytes[field + index] = UInt8((duration >> ((width - index - 1) * 8)) & 0xff) }
        }
        try Data(bytes).write(to: url, options: .atomic)
    }
}
