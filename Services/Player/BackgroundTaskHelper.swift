import Foundation
#if os(iOS)
import UIKit
#endif

/// Requests finite, best-effort execution time when an operation enters the background.
enum BackgroundTaskHelper {
    /// Releases the iOS execution assertion on completion or expiration, whichever comes first.
    /// Expiration does not cancel the operation or guarantee that it finishes before suspension.
    /// Callers must persist enough state to recover if the process is terminated.
    /// On macOS, this is a no-op passthrough.
    ///
    /// - Parameter operation: The async operation to execute
    /// - Returns: The result of the operation
    @MainActor
    static func withBackgroundTask<T>(_ operation: () async throws -> T) async rethrows -> T {
        #if os(iOS)
        let lease = BackgroundTaskLease()
        lease.start()
        defer { lease.end() }

        return try await operation()
        #else
        return try await operation()
        #endif
    }
}

#if os(iOS)
/// UIKit invokes its expiration handler synchronously on the main actor.
/// Keeping the identifier here avoids concurrent mutation of a captured local variable.
@MainActor
private final class BackgroundTaskLease {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var hasEnded = false

    func start() {
        let granted = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.end()
        }
        // Also handle expiration during the registration call before its result is stored.
        if hasEnded {
            if granted != .invalid { UIApplication.shared.endBackgroundTask(granted) }
        } else {
            identifier = granted
        }
    }

    func end() {
        guard !hasEnded else { return }
        hasEnded = true
        let taskID = identifier
        identifier = .invalid
        if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
    }
}
#endif
