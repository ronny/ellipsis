import Foundation

/// Where Ellipsis runs from. `MenuBarAgent` matches the allow-list only
/// against apps in `/Applications` (`docs/phase0.md`), so a restriction
/// held by a copy anywhere else hides the Ellipsis icon too. App
/// Translocation is the case a user meets: macOS runs a quarantined app
/// that was not moved by Finder from a random folder, even when the app
/// itself sits in `/Applications`.
struct AppLocation: Equatable {
    /// The bundle that runs.
    let bundlePath: String
    /// The bundle macOS translocated from, or nil when it runs in place.
    let originalPath: String?

    var isTranslocated: Bool { originalPath != nil }

    /// Whether `MenuBarAgent` can allow-list Ellipsis, so a restriction
    /// leaves its icon in the menu bar. Only the top level of
    /// `/Applications` is tested; anything else counts as not.
    var canHide: Bool {
        !isTranslocated && Self.isInApplications(bundlePath)
    }

    /// The apps a restriction may hide. Nothing while the icon would hide
    /// with them, and never Ellipsis itself, whatever the sets say.
    func identifiersToHide(_ wanted: Set<String>, own: String?) -> Set<String> {
        guard canHide else { return [] }
        guard let own else { return wanted }
        return wanted.subtracting([own])
    }

    // MARK: Moving to /Applications

    /// The bundle's file name without `.app`, the name the user sees in the Finder.
    var appName: String {
        ((source as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// The bundle a move starts from: the original, not the translocated copy.
    var source: String { Self.standardized(originalPath ?? bundlePath) }

    var destination: String {
        "/Applications/" + (source as NSString).lastPathComponent
    }

    /// False when the original already sits at the destination, and only
    /// its quarantine keeps it translocated.
    var needsCopy: Bool { source != destination }

    private static func isInApplications(_ path: String) -> Bool {
        (standardized(path) as NSString).deletingLastPathComponent == "/Applications"
    }

    private static func standardized(_ path: String) -> String {
        (path as NSString).standardizingPath
    }
}
