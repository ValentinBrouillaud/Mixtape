import CryptoKit
import Foundation
import Observation

/// Keeps small history thumbnails across launches without downloading audio.
@MainActor
@Observable
final class HistoryArtworkCache {
    static let shared = HistoryArtworkCache()
    nonisolated static let maximumImageBytes = 1_000_000

    private(set) var revision = 0
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var files: [String: URL] = [:]
    @ObservationIgnored private var retainedIDs: Set<String> = []
    @ObservationIgnored private var sources: [String: URL] = [:]
    @ObservationIgnored private var order: [String] = []
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var tokens: [String: UUID] = [:]
    @ObservationIgnored private var failed: Set<String> = []

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Mixtape", isDirectory: true)
            .appendingPathComponent("HistoryArtwork", isDirectory: true)
    }

    func cachedFileURL(videoId: String) -> URL? {
        _ = revision // Observe finished writes even though the file index is private.
        return files[videoId]
    }

    /// Cancel removed entries immediately and retain at most the history's 100 images.
    func retain(entries: [ListeningHistoryEntry]) {
        let entries = ListeningHistoryPolicy.normalized(entries)
        retainedIDs = Set(entries.map(\.videoId))
        order = entries.map(\.videoId)
        sources = Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
            guard let url = entry.artworkURL, url.scheme?.lowercased() == "https" else { return nil }
            return (entry.videoId, url)
        })
        failed.removeAll()
        for id in Array(tasks.keys) where !retainedIDs.contains(id) {
            tasks.removeValue(forKey: id)?.cancel()
            tokens.removeValue(forKey: id)
        }

        let previous = files
        files.removeAll()
        let names = Set(entries.map { fileURL(videoId: $0.videoId).lastPathComponent })
        for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            if !names.contains(url.lastPathComponent) { try? FileManager.default.removeItem(at: url) }
        }
        for entry in entries {
            let url = fileURL(videoId: entry.videoId)
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > 0, size <= Self.maximumImageBytes {
                files[entry.videoId] = url
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
        if previous != files {
            revision &+= 1
            WidgetSnapshotBridge.shared.refreshArtwork()
        }
        scheduleDownloads()
    }

    private func fileURL(videoId: String) -> URL {
        let digest = SHA256.hash(data: Data(videoId.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".image")
    }

    private func scheduleDownloads() {
        for id in order {
            guard tasks.count < 3 else { return }
            guard tasks[id] == nil, files[id] == nil, !failed.contains(id), let source = sources[id] else { continue }
            let token = UUID()
            tokens[id] = token
            tasks[id] = Task { [weak self] in
                guard let self else { return }
                defer {
                    if self.tokens[id] == token {
                        self.tasks.removeValue(forKey: id)
                        self.tokens.removeValue(forKey: id)
                        self.scheduleDownloads()
                    }
                }
                do {
                    let data = try await Self.fetchImage(source)
                    try Task.checkCancellation()
                    guard self.retainedIDs.contains(id), self.tokens[id] == token else { return }
                    let target = self.fileURL(videoId: id)
                    try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
                    try data.write(to: target, options: .atomic)
                    self.files[id] = target
                    self.revision &+= 1
                    WidgetSnapshotBridge.shared.refreshArtwork()
                } catch {
                    if self.tokens[id] == token, !Task.isCancelled { self.failed.insert(id) }
                }
            }
        }
    }

    @concurrent private static func fetchImage(_ url: URL) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpShouldHandleCookies = false
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.mimeType?.lowercased().hasPrefix("image/") == true,
              response.expectedContentLength <= Int64(maximumImageBytes) else { throw CocoaError(.fileReadCorruptFile) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumImageBytes else { throw CocoaError(.fileReadTooLarge) }
            data.append(byte)
        }
        return try HistoryThumbnail.encode(data)
    }
}
