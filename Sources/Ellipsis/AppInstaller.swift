import Foundation

/// The file work behind "Move to Applications". `applications` is
/// `/Applications` in the app and a temporary folder in tests.
struct AppInstaller {
    static let quarantineAttribute = "com.apple.quarantine"

    var applications = URL(fileURLWithPath: "/Applications")

    /// What `Info.plist` says about a bundle.
    struct Info: Equatable {
        var bundleIdentifier: String?
        var version: String?
        var build: String?

        /// Compares the version, then the build, as numbers: 1.10 is newer than 1.9.
        func isNewer(than other: Info) -> Bool {
            let pairs = [(version, other.version), (build, other.build)]
            for case let (mine?, theirs?) in pairs {
                switch mine.compare(theirs, options: .numeric) {
                case .orderedDescending: return true
                case .orderedAscending: return false
                case .orderedSame: continue
                }
            }
            return false
        }
    }

    enum Plan: Equatable {
        /// The source already is the bundle in `applications`; only its
        /// quarantine has to go.
        case inPlace(URL)
        /// `existing` is the bundle the copy replaces, if any.
        case copy(from: URL, to: URL, existing: Info?, incoming: Info)
    }

    enum Failure: LocalizedError, Equatable {
        case sourceMissing(String)
        case differentApp(existing: String)
        case quarantine(path: String, errno: Int32)

        var errorDescription: String? {
            switch self {
            case .sourceMissing(let path):
                "The app is no longer at \(path)."
            case .differentApp(let existing):
                "The Applications folder already has a different app with the same name (\(existing))."
            case .quarantine(let path, let code):
                "The quarantine of \(path) could not be removed: \(String(cString: strerror(code)))."
            }
        }
    }

    /// Reads the file system now, so a plan made at click time sees moves
    /// that happened since launch.
    func plan(source: URL) throws -> Plan {
        let source = source.standardizedFileURL
        guard FileManager.default.fileExists(atPath: source.path), let incoming = Self.info(of: source) else {
            throw Failure.sourceMissing(source.path)
        }
        let destination = applications.appendingPathComponent(source.lastPathComponent)
        if AppLocation.isSameItem(source, destination) {
            return .inPlace(destination)
        }
        guard FileManager.default.fileExists(atPath: destination.path) else {
            return .copy(from: source, to: destination, existing: nil, incoming: incoming)
        }
        let existing = Self.info(of: destination)
        guard let existing, existing.bundleIdentifier == incoming.bundleIdentifier else {
            throw Failure.differentApp(existing: existing?.bundleIdentifier ?? destination.lastPathComponent)
        }
        return .copy(from: source, to: destination, existing: existing, incoming: incoming)
    }

    /// Copies to a staging folder on the destination volume, clears the
    /// quarantine there, and only then swaps the copy in. A failure at any
    /// step leaves the bundle in `applications` as it was.
    func install(_ plan: Plan) throws {
        switch plan {
        case .inPlace(let destination):
            try Self.clearQuarantine(destination)
        case .copy(let source, let destination, _, _):
            let files = FileManager.default
            let staging = try files.url(
                for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true
            )
            defer { try? files.removeItem(at: staging) }
            let staged = staging.appendingPathComponent(destination.lastPathComponent)
            try files.copyItem(at: source, to: staged)
            try Self.clearQuarantine(staged)
            if files.fileExists(atPath: destination.path) {
                _ = try files.replaceItemAt(destination, withItemAt: staged)
            } else {
                try files.moveItem(at: staged, to: destination)
            }
        }
    }

    /// Moves the source of a finished copy to the Trash, as a Finder move
    /// would leave nothing behind. Not from a read-only volume such as a
    /// disk image, and not from a folder the user cannot write.
    static func trashSource(_ source: URL) throws {
        let values = try source.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        guard values.volumeIsReadOnly != true,
              FileManager.default.isWritableFile(atPath: source.deletingLastPathComponent().path)
        else { return }
        try FileManager.default.trashItem(at: source, resultingItemURL: nil)
    }

    static func info(of bundle: URL) -> Info? {
        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: plist),
            let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return Info(
            bundleIdentifier: values["CFBundleIdentifier"] as? String,
            version: values["CFBundleShortVersionString"] as? String,
            build: values["CFBundleVersion"] as? String
        )
    }

    /// Removes the quarantine from the bundle and everything in it, in
    /// process, so a refusal such as App Management's surfaces as an error.
    static func clearQuarantine(_ bundle: URL) throws {
        var paths = [bundle.path]
        if let contents = FileManager.default.enumerator(atPath: bundle.path) {
            for case let relative as String in contents {
                paths.append(bundle.appendingPathComponent(relative).path)
            }
        }
        for path in paths where removexattr(path, quarantineAttribute, XATTR_NOFOLLOW) != 0 && errno != ENOATTR {
            throw Failure.quarantine(path: path, errno: errno)
        }
    }
}
