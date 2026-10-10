import Foundation

/// Drops the second icon action of one physical click. After a wake,
/// MenuBarAgent can deliver every click to the status item twice, a
/// millisecond apart. Two toggles show and hide again before the
/// restriction is reapplied, so the click seems to do nothing. See
/// GitHub issue #3.
struct ClickDebounce {
    /// Well under the fastest human double-click, well over the 1–2 ms
    /// between the duplicates.
    static let window: TimeInterval = 0.1

    private var lastAccepted: TimeInterval?

    /// `time` is monotonic seconds, such as `ProcessInfo.systemUptime`.
    mutating func accept(at time: TimeInterval) -> Bool {
        if let lastAccepted, time - lastAccepted < Self.window {
            return false
        }
        lastAccepted = time
        return true
    }
}
