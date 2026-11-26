import Foundation

nonisolated enum MixtapeWidgetReadIssue: String, Equatable, Sendable {
    case sharedContainerUnavailable
    case noSnapshot
    case unreadableSnapshot
}

nonisolated struct MixtapeWidgetReadResult: Equatable, Sendable {
    let snapshot: MixtapeWidgetSnapshot
    let issue: MixtapeWidgetReadIssue?
}

/// Written explicitly by widget providers, never by the containing application.
nonisolated struct MixtapeWidgetReadReceipt: Codable, Equatable, Sendable {
    let readAt: Date
    let snapshotUpdatedAt: Date
    let appGroupIdentifier: String
}

/// Both targets read this small, atomic metadata snapshot. The extension never loads audio.
nonisolated enum MixtapeWidgetStorage {
    static let appGroup = "group.com.alexcding.mixtape"
    static let snapshotFileName = "widget-snapshot.json"
    static let receiptFileName = "widget-read-receipt.json"
    private static let maximumSnapshotBytes = 2 * 1024 * 1024
    static let environment = MixtapeWidgetEnvironment.inspect(bundleURL: Bundle.main.bundleURL)

    // Entitlements cannot change during a process lifetime. Resolve once rather
    // than parsing a profile on every artwork lookup or playback update.
    private static let resolvedContainer: (identifier: String, url: URL)? = {
        for identifier in environment.candidates {
            // Profile content supplies name hints only. The OS sandbox remains
            // responsible for allowing access to the actual shared container.
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
                return (identifier, url.appendingPathComponent("MixtapeWidgets", isDirectory: true))
            }
        }
        return nil
    }()

    static var resolvedAppGroupIdentifier: String? { resolvedContainer?.identifier }
    static var containerURL: URL? { resolvedContainer?.url }

    static func load() -> MixtapeWidgetSnapshot { read().snapshot }

    static func read() -> MixtapeWidgetReadResult { read(at: containerURL) }

    /// `root` is the MixtapeWidgets directory within an authorized App Group.
    /// An injectable directory keeps disk behavior testable without signing.
    static func read(at root: URL?) -> MixtapeWidgetReadResult {
        guard let root else { return MixtapeWidgetReadResult(snapshot: .empty, issue: .sharedContainerUnavailable) }
        do {
            let data = try readSmallFile(at: root.appendingPathComponent(snapshotFileName), maximumBytes: maximumSnapshotBytes)
            let snapshot = try JSONDecoder().decode(MixtapeWidgetSnapshot.self, from: data)
            return MixtapeWidgetReadResult(snapshot: snapshot, issue: nil)
        } catch {
            let error = error as NSError
            let absent = error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)
            return MixtapeWidgetReadResult(snapshot: .empty, issue: absent ? .noSnapshot : .unreadableSnapshot)
        }
    }

    /// Providers call this after a successful read. A normal app read must not
    /// manufacture proof that a separate widget extension received its data.
    @discardableResult
    static func acknowledge(_ result: MixtapeWidgetReadResult, at date: Date = Date()) -> Bool {
        acknowledge(result, in: containerURL, appGroupIdentifier: resolvedAppGroupIdentifier, at: date)
    }

    @discardableResult
    static func acknowledge(
        _ result: MixtapeWidgetReadResult, in root: URL?, appGroupIdentifier: String?, at date: Date = Date()
    ) -> Bool {
        guard result.issue == nil, let root, let appGroupIdentifier,
              MixtapeWidgetGroupResolver.isValidIdentifier(appGroupIdentifier) else { return false }
        do {
            let receipt = MixtapeWidgetReadReceipt(
                readAt: date, snapshotUpdatedAt: result.snapshot.updatedAt, appGroupIdentifier: appGroupIdentifier
            )
            let data = try JSONEncoder().encode(receipt)
            try data.write(to: root.appendingPathComponent(receiptFileName), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func lastReceipt() -> MixtapeWidgetReadReceipt? {
        guard let receipt = lastReceipt(at: containerURL), receipt.appGroupIdentifier == resolvedAppGroupIdentifier else { return nil }
        return receipt
    }

    static func lastReceipt(at root: URL?) -> MixtapeWidgetReadReceipt? {
        guard let root,
              let data = try? readSmallFile(at: root.appendingPathComponent(receiptFileName), maximumBytes: 8 * 1024),
              let receipt = try? JSONDecoder().decode(MixtapeWidgetReadReceipt.self, from: data),
              MixtapeWidgetGroupResolver.isValidIdentifier(receipt.appGroupIdentifier) else { return nil }
        return receipt
    }

    static func artworkURL(fileName: String?) -> URL? {
        guard let fileName, !fileName.isEmpty, fileName == (fileName as NSString).lastPathComponent,
              ![".", ".."].contains(fileName), let root = containerURL else { return nil }
        return root.appendingPathComponent("Artwork", isDirectory: true).appendingPathComponent(fileName)
    }

    private static func readSmallFile(at url: URL, maximumBytes: Int) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var data = Data()
        while data.count <= maximumBytes {
            let capacity = min(64 * 1024, maximumBytes + 1 - data.count)
            guard let chunk = try file.read(upToCount: capacity), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        guard data.count <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        return data
    }
}
