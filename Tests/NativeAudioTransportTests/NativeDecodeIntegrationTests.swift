import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import NativeAudioTransport

// Extend the serialized HTTP suite: its cancellation tests also assert that no
// temporary offline files remain, so real-media transfers must run in that suite.
extension NativeRangeIntegrationTests {
    @Test @MainActor func nativeResourceLoaderDecodesSignalAfterLeadInAndSeek() async throws {
        let media = try NativeDecodeFixture.makeAAC()
        defer { try? FileManager.default.removeItem(at: media) }
        let server = try AudioHTTPFixture(mediaURL: media)
        defer { server.stop() }
        let loader = HTTPAudioResourceLoader(remoteURL: server.url("range"), headers: NativeDecodeFixture.headers)
        defer { loader.invalidate() }
        let asset = AVURLAsset(url: loader.assetURL)
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)

        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try #require(tracks.first)
        let start = try NativeDecodeFixture.decode(asset: asset, track: track, start: 0.2)
        let afterSeek = try NativeDecodeFixture.decode(asset: asset, track: track, start: 2)
        #expect(start.samples > 4000)
        #expect(start.rms < 0.005)
        #expect(afterSeek.samples > 4000)
        #expect(afterSeek.rms > 0.08)
        // This checks decoded bytes supplied by the custom native loader. It
        // does not claim that an iPhone speaker or YouTube playback was tested.
    }

    @Test @MainActor func downloadedAACPreservesBytesAndDecodedSignalAcrossFile() async throws {
        let media = try NativeDecodeFixture.makeAAC()
        defer { try? FileManager.default.removeItem(at: media) }
        let server = try AudioHTTPFixture(mediaURL: media)
        defer { server.stop() }
        let saved = try await MixtapeHTTPAudioTransfer.fetch(
            url: server.url("range"), expectedBytes: 0,
            userAgent: NativeDecodeFixture.headers["User-Agent"]!, progress: { _ in }
        )
        defer { try? FileManager.default.removeItem(at: saved) }
        #expect(try Data(contentsOf: saved) == Data(contentsOf: media))
        let file = try AVAudioFile(forReading: saved, commonFormat: .pcmFormatFloat32, interleaved: false)
        let beginning = try NativeDecodeFixture.read(file, at: 0.2)
        let middle = try NativeDecodeFixture.read(file, at: 2)
        let end = try NativeDecodeFixture.read(file, at: 3.5)
        #expect(beginning.samples > 4000)
        #expect(beginning.rms < 0.005)
        #expect(middle.samples > 4000)
        #expect(middle.rms > 0.08)
        #expect(end.samples > 4000)
        #expect(end.rms > 0.08)
    }
}

@MainActor
private enum NativeDecodeFixture {
    static let sampleRate = 44_100.0
    static let headers = [
        "User-Agent": "MixtapeTransportTests/1.0",
        "Origin": "https://www.youtube.com",
        "Referer": "https://www.youtube.com/",
    ]

    private enum Failure: Error { case allocation, encoding, decoding, sampleBuffer }

    struct Signal {
        let samples: Int
        let rms: Double
    }

    /// One second of genuine silence, then three seconds of a 440 Hz tone. AAC
    /// encoder padding cannot make a silent beginning satisfy the later checks.
    static func makeAAC() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mixtape-test-tone-\(UUID().uuidString).m4a")
        do {
            guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleRate * 4)),
                  let channel = buffer.floatChannelData?[0] else { throw Failure.allocation }
            buffer.frameLength = buffer.frameCapacity
            for frame in 0..<Int(buffer.frameLength) {
                let time = Double(frame) / sampleRate
                channel[frame] = time < 1 ? 0 : Float(0.25 * sin(2 * .pi * 440 * time))
            }
            // The writer leaves this scope before the file is served, ensuring
            // the MP4 metadata and AAC packets have been finalized.
            do {
                let writer = try AVAudioFile(
                    forWriting: url,
                    settings: [
                        AVFormatIDKey: kAudioFormatMPEG4AAC,
                        AVSampleRateKey: sampleRate,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderBitRateKey: 128_000,
                    ],
                    commonFormat: .pcmFormatFloat32,
                    interleaved: false
                )
                try writer.write(from: buffer)
            }
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// A second reader at an absolute time exercises the same remote asset after
    /// seeking, including requests for MP4 metadata at the end of the file.
    static func decode(asset: AVAsset, track: AVAssetTrack, start: Double) throws -> Signal {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                       duration: CMTime(seconds: 0.25, preferredTimescale: 600))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else { throw Failure.decoding }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? Failure.decoding }
        var count = 0
        var energy = 0.0
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { throw Failure.sampleBuffer }
            let byteCount = CMBlockBufferGetDataLength(block)
            guard byteCount > 0, byteCount.isMultiple(of: MemoryLayout<Float>.size) else { throw Failure.sampleBuffer }
            var values = [Float](repeating: 0, count: byteCount / MemoryLayout<Float>.size)
            let result = values.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteCount, destination: bytes.baseAddress!)
            }
            guard result == kCMBlockBufferNoErr else { throw Failure.sampleBuffer }
            for value in values { energy += Double(value) * Double(value) }
            count += values.count
        }
        guard reader.status == .completed else { throw reader.error ?? Failure.decoding }
        return Signal(samples: count, rms: count > 0 ? sqrt(energy / Double(count)) : 0)
    }

    static func read(_ file: AVAudioFile, at seconds: Double) throws -> Signal {
        file.framePosition = AVAudioFramePosition(seconds * file.processingFormat.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 11_025) else {
            throw Failure.allocation
        }
        try file.read(into: buffer)
        guard let values = buffer.floatChannelData?[0] else { throw Failure.decoding }
        let count = Int(buffer.frameLength)
        var energy = 0.0
        for index in 0..<count { energy += Double(values[index]) * Double(values[index]) }
        return Signal(samples: count, rms: count > 0 ? sqrt(energy / Double(count)) : 0)
    }
}
