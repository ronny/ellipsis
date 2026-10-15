import AppKit
import os

extension NSWorkspace {
    /// Yields when an app starts or quits. `didLaunchApplicationNotification`
    /// is not posted for `LSUIElement` apps, and apps with a menu bar item
    /// mostly are, so this watches `runningApplications` instead. That list
    /// also changes for every short-lived process that touches AppKit, such
    /// as a script a menu bar tool runs every second. Those processes have no
    /// bundle identifier, so only a change in the bundle identifiers yields.
    static func runningApplicationChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let last = OSAllocatedUnfairLock(initialState: runningBundleIdentifiers())
            let observation = shared.observe(\.runningApplications) { _, _ in
                let current = runningBundleIdentifiers()
                let changed = last.withLock { last in
                    defer { last = current }
                    return last != current
                }
                if changed {
                    continuation.yield()
                }
            }
            continuation.onTermination = { _ in observation.invalidate() }
        }
    }

    private static func runningBundleIdentifiers() -> Set<String> {
        Set(shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}
