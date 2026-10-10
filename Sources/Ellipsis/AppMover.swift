import AppKit
import os

extension AppLocation {
    /// The location of the running bundle. The SecTranslocate calls are
    /// exported by Security.framework but have no public header.
    static func current() -> AppLocation {
        let url = Bundle.main.bundleURL
        return AppLocation(bundlePath: url.path, originalPath: translocationOriginal(of: url)?.path)
    }

    private typealias IsTranslocated = @convention(c) (
        CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?
    ) -> DarwinBoolean
    private typealias OriginalPath = @convention(c) (
        CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?
    ) -> Unmanaged<CFURL>?

    private static func translocationOriginal(of url: URL) -> URL? {
        guard
            let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW),
            let isSymbol = dlsym(security, "SecTranslocateIsTranslocatedURL"),
            let originalSymbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL")
        else { return nil }
        let isTranslocated = unsafeBitCast(isSymbol, to: IsTranslocated.self)
        let originalPath = unsafeBitCast(originalSymbol, to: OriginalPath.self)
        var translocated = false
        guard isTranslocated(url as CFURL, &translocated, nil).boolValue, translocated else { return nil }
        return originalPath(url as CFURL, nil)?.takeRetainedValue() as URL?
    }
}

/// Offers to move Ellipsis to `/Applications` and relaunch it there, where
/// `MenuBarAgent` can allow-list its icon. See `AppLocation`.
@MainActor
enum AppMover {
    private static let log = Logger(subsystem: "au.ronny.Ellipsis", category: "location")

    static func offerMove(_ location: AppLocation) {
        let name = location.appName
        let alert = NSAlert()
        alert.messageText = "Move \(name) to the Applications folder?"
        let reason = location.isTranslocated
            ? "macOS runs a temporary copy of \(name), because the app was not moved with the Finder. macOS hides the icon of this copy with the other items."
            : "\(name) is not in the Applications folder, so macOS hides its icon with the other items."
        alert.informativeText = """
            \(reason) Until \(name) runs from the Applications folder, it hides nothing.

            \(name) can move itself there and open again.
            """
        alert.addButton(withTitle: "Move and Relaunch")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try move(location)
            relaunch(at: location.destination)
        } catch {
            log.error("move failed: \(String(describing: error), privacy: .public)")
            let failure = NSAlert(error: error)
            failure.messageText = "\(name) could not move itself"
            failure.informativeText = """
                Quit \(name). Move it to the Applications folder with the Finder, then open it again.

                \(error.localizedDescription)
                """
            failure.runModal()
        }
    }

    /// Copies the original bundle to `/Applications` when it is not there,
    /// and clears its quarantine. A quarantined app that the Finder did not
    /// move is translocated again at its next launch.
    private static func move(_ location: AppLocation) throws {
        let destination = URL(fileURLWithPath: location.destination)
        let files = FileManager.default
        if location.needsCopy {
            if files.fileExists(atPath: destination.path) {
                try files.trashItem(at: destination, resultingItemURL: nil)
            }
            try files.copyItem(at: URL(fileURLWithPath: location.source), to: destination)
        }
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-d", "-r", "com.apple.quarantine", destination.path]
        try xattr.run()
        xattr.waitUntilExit()
        log.notice("moved to \(destination.path, privacy: .public), copied \(location.needsCopy)")
    }

    /// Opens the new copy once this process has quit, so two instances
    /// never hold a restriction at once.
    private static func relaunch(at path: String) {
        let opener = Process()
        opener.executableURL = URL(fileURLWithPath: "/bin/sh")
        opener.arguments = [
            "-c", #"while kill -0 "$1" 2>/dev/null; do sleep 0.1; done; open "$2""#,
            "sh", String(ProcessInfo.processInfo.processIdentifier), path,
        ]
        try? opener.run()
        NSApp.terminate(nil)
    }
}
