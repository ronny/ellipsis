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
    /// `/Applications` is tested; anything else counts as not. The folder
    /// is compared on disk, so `/System/Volumes/Data/Applications` and
    /// `/applications` count too.
    var canHide: Bool {
        guard !isTranslocated else { return false }
        let folder = URL(fileURLWithPath: bundlePath).standardizedFileURL.deletingLastPathComponent()
        return Self.isSameItem(folder, URL(fileURLWithPath: "/Applications"))
    }

    /// The apps a restriction may hide. Nothing while the icon would hide
    /// with them, and never Ellipsis itself, whatever the sets say.
    func identifiersToHide(_ wanted: Set<String>, own: String?) -> Set<String> {
        guard canHide else { return [] }
        guard let own else { return wanted }
        return wanted.subtracting([own])
    }

    /// The bundle a move starts from: the original, not the translocated copy.
    var source: String { ((originalPath ?? bundlePath) as NSString).standardizingPath }

    /// The bundle's file name without `.app`, the name the user sees in the Finder.
    var appName: String {
        ((source as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// Whether two URLs name the same file or folder on disk, whatever the
    /// spelling. False when either does not exist.
    static func isSameItem(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard
            let first = try? a.resourceValues(forKeys: key).fileResourceIdentifier,
            let second = try? b.resourceValues(forKeys: key).fileResourceIdentifier
        else { return false }
        return first.isEqual(second)
    }
}
