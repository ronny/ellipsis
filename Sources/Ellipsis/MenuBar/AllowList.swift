/// What the newest assertion hides and allows, so a reapply that would
/// change nothing is skipped. Each assertion makes MenuBarAgent lay out
/// the menu bar again. A helper that starts and quits every second would
/// otherwise keep it busy for good, and icon clicks get lost. See GitHub
/// issue #3.
struct AllowList {
    private var hidden: Set<String>?
    private var allowed: Set<String> = []

    /// Whether an assertion for `hidden` and `allowed` would show or hide
    /// something the newest one does not. An allowed app that quit can stay
    /// in the list: it does no harm, and its next launch needs no reapply.
    func needsApply(hidden: Set<String>, allowed: Set<String>) -> Bool {
        hidden != self.hidden || !allowed.isSubset(of: self.allowed)
    }

    mutating func record(hidden: Set<String>, allowed: Set<String>) {
        self.hidden = hidden
        self.allowed = allowed
    }

    mutating func clear() {
        hidden = nil
        allowed = []
    }
}
