import Foundation
import ImageIO
import Security

/// Metadata-only fallback for re-signers that omit the file App Group. Profile
/// values supply hints; every read/write is authorized by Keychain Services.
/// Nothing here adds entitlements, touches login tokens or accesses other items.
nonisolated enum MixtapeWidgetKeychain {
    static let service = "com.alexcding.mixtape.widget-metadata.v1"
    static let maximumPayloadBytes = 1024 * 1024
    static let maximumArtworkBytes = 32 * 1024
    static let maximumArtworkCount = 16

    struct Candidate: Equatable, Sendable {
        let group: String?
        var identifier: String { "keychain:" + (group ?? "default") }
    }

    struct Payload: Codable, Equatable, Sendable {
        var version = 1
        let snapshot: MixtapeWidgetSnapshot
        let artwork: [String: Data]
    }

    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Widget keychain: \(status)" }
    }

    static func candidates(in environment: MixtapeWidgetEnvironment) -> [Candidate] {
        guard environment.widgetIdentifier != nil,
              environment.issue != .conflictingIdentifiers else { return [] }
        let app = environment.appProfile
        let widget = environment.widgetProfile
        // Sideloadly may omit the extension's embedded profile. Its renamed
        // bundle ID is another name hint when the parent profile is unreadable.
        let bundleHint = [environment.appIdentifier, environment.widgetIdentifier].compactMap { $0 }
            .filter { $0.hasPrefix("com.alexcding.mixtape.") }
            .flatMap { $0.split(separator: ".").map(String.init) }
            .first { $0.utf8.count == 10 && $0.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }) }
        let prefix = app?.appIdentifierPrefix ?? app?.teamIdentifier ?? widget?.appIdentifierPrefix ?? widget?.teamIdentifier ?? bundleHint
        guard let prefix, prefix.utf8.count == 10,
              prefix.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }) else { return [] }
        if let other = widget?.appIdentifierPrefix ?? widget?.teamIdentifier, other != prefix { return [] }
        var groups = [prefix + ".com.alexcding.mixtape.widgets.shared"]
        if let host = environment.appIdentifier, host.hasPrefix("com.alexcding.mixtape") { groups.append(prefix + "." + host) }
        // Some re-signers copy the same literal wildcard into both signatures.
        // Try that exact group only when present in a profile; do not treat it
        // as authority to choose arbitrary keychain groups.
        let hints = (app?.keychainGroups ?? []) + (widget?.keychainGroups ?? [])
        if hints.contains(prefix + ".*") { groups.append(prefix + ".*") }
        var seen = Set<String>()
        var result = groups.filter { seen.insert($0).inserted }.map { Candidate(group: $0) }
        // A default-group read may reach a shared item on re-signers using the
        // host identity for extensions. A successful app write alone is never
        // presented as proof that a widget can read that item.
        result.append(Candidate(group: nil))
        return result
    }

    static func encode(_ payload: Payload) throws -> Data {
        guard payload.version == 1, payload.artwork.count <= maximumArtworkCount,
              payload.artwork.allSatisfy({ validFileName($0.key) && $0.value.count <= maximumArtworkBytes }) else {
            throw CocoaError(.coderInvalidValue)
        }
        let data = try JSONEncoder().encode(payload)
        guard data.count <= maximumPayloadBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        return data
    }

    static func decode(_ data: Data) throws -> Payload {
        guard data.count <= maximumPayloadBytes else { throw CocoaError(.fileReadTooLarge) }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.version == 1, payload.artwork.count <= maximumArtworkCount,
              payload.artwork.allSatisfy({ validFileName($0.key) && $0.value.count <= maximumArtworkBytes }) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return payload
    }

    static func publish(_ snapshot: MixtapeWidgetSnapshot, sources: [String: URL]) throws -> String {
        let files = Set(([snapshot.currentSong?.artworkFileName].compactMap { $0 })
            + snapshot.recentSongs.prefix(4).compactMap(\.artworkFileName)
            + snapshot.playlists.prefix(8).compactMap(\.artworkFileName))
        var artwork: [String: Data] = [:]
        for name in files.sorted().prefix(maximumArtworkCount) {
            if let source = sources[name], let data = thumbnail(at: source) { artwork[name] = data }
        }
        let data = try encode(Payload(snapshot: snapshot, artwork: artwork))
        return try publish(candidates: candidates(in: MixtapeWidgetStorage.environment)) { candidate in
            write(data, account: "snapshot", candidate: candidate)
        }
    }

    static func publish(candidates: [Candidate], write: (Candidate) -> OSStatus) throws -> String {
        var status = errSecMissingEntitlement
        for candidate in candidates {
            status = write(candidate)
            if status == errSecSuccess { return candidate.identifier }
        }
        throw Failure(status: status)
    }

    static func read() -> MixtapeWidgetReadResult {
        let (result, payload) = load(candidates: candidates(in: MixtapeWidgetStorage.environment)) { candidate in
            read(account: "snapshot", candidate: candidate)
        }
        if let payload { cacheArtwork(payload.artwork) }
        return result
    }

    static func load(candidates: [Candidate], fetch: (Candidate) -> (OSStatus, Data?)) -> (MixtapeWidgetReadResult, Payload?) {
        var newest: (Payload, Candidate)?
        var sawMissing = false
        var sawCorrupt = false
        for candidate in candidates {
            let (status, data) = fetch(candidate)
            sawMissing = sawMissing || status == errSecItemNotFound
            guard status == errSecSuccess, let data else { continue }
            guard let payload = try? decode(data) else { sawCorrupt = true; continue }
            if let current = newest, current.0.snapshot.updatedAt >= payload.snapshot.updatedAt { continue }
            newest = (payload, candidate)
        }
        guard let (payload, candidate) = newest else {
            return (MixtapeWidgetReadResult(snapshot: .empty,
                issue: sawCorrupt ? .unreadableSnapshot : (sawMissing ? .noSnapshot : .sharedContainerUnavailable)), nil)
        }
        return (MixtapeWidgetReadResult(snapshot: payload.snapshot, issue: nil, sharedIdentifier: candidate.identifier), payload)
    }

    static func acknowledge(_ result: MixtapeWidgetReadResult, at date: Date) -> Bool {
        guard result.issue == nil, let identifier = result.sharedIdentifier,
              let candidate = candidates(in: MixtapeWidgetStorage.environment).first(where: { $0.identifier == identifier }),
              let data = try? JSONEncoder().encode(MixtapeWidgetReadReceipt(
                  readAt: date, snapshotUpdatedAt: result.snapshot.updatedAt, appGroupIdentifier: identifier
              )) else { return false }
        return write(data, account: "receipt", candidate: candidate) == errSecSuccess
    }

    static func lastReceipt() -> MixtapeWidgetReadReceipt? {
        candidates(in: MixtapeWidgetStorage.environment).compactMap { candidate -> MixtapeWidgetReadReceipt? in
            let (status, data) = read(account: "receipt", candidate: candidate)
            guard status == errSecSuccess, let data, data.count <= 8 * 1024,
                  let receipt = try? JSONDecoder().decode(MixtapeWidgetReadReceipt.self, from: data),
                  candidates(in: MixtapeWidgetStorage.environment).contains(where: { $0.identifier == receipt.appGroupIdentifier }) else { return nil }
            return receipt
        }.max { $0.readAt < $1.readAt }
    }

    static var artworkDirectory: URL {
        (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("MixtapeWidgetKeychainArtwork", isDirectory: true)
    }

    private static func cacheArtwork(_ artwork: [String: Data]) {
        let directory = artworkDirectory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, data) in artwork where validFileName(name) {
                try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            }
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                if artwork[file.lastPathComponent] == nil { try? FileManager.default.removeItem(at: file) }
            }
        } catch { /* Titles remain usable if the extension's artwork cache is full. */ }
    }

    static func thumbnail(at url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 192,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
        guard CGImageDestinationFinalize(destination), data.length <= maximumArtworkBytes else { return nil }
        return data as Data
    }

    private static func validFileName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 255 && name == (name as NSString).lastPathComponent && name != "." && name != ".."
    }

    private static func query(account: String, candidate: Candidate) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
        if let group = candidate.group { query[kSecAttrAccessGroup as String] = group }
        return query
    }

    private static func read(account: String, candidate: Candidate) -> (OSStatus, Data?) {
        var query = query(account: account, candidate: candidate)
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    private static func write(_ data: Data, account: String, candidate: Candidate) -> OSStatus {
        var query = query(account: account, candidate: candidate)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status != errSecItemNotFound { return status }
        query.merge(attributes) { _, new in new }
        return SecItemAdd(query as CFDictionary, nil)
    }
}
