import AppKit
import os

/// Offers to move Ellipsis to `/Applications` and relaunch it there, where
/// `MenuBarAgent` can allow-list its icon. See `AppLocation`; the file
/// work is in `AppInstaller`.
@MainActor
enum AppMover {
    private static let log = Logger(subsystem: "au.ronny.Ellipsis", category: "location")
    private static var isOffering = false

    enum MoveError: LocalizedError {
        case stillRunning(String)

        var errorDescription: String? {
            switch self {
            case .stillRunning(let path): "The copy at \(path) did not quit."
            }
        }
    }

    static func offerMove() {
        guard !isOffering else { return }
        isOffering = true
        Task {
            await offer()
            isOffering = false
        }
    }

    private static func offer() async {
        // Read now, not at launch: the user can have moved the app since.
        let location = AppLocation.current()
        let name = location.appName
        let installer = AppInstaller()
        do {
            let plan = try installer.plan(source: URL(fileURLWithPath: location.source))
            guard confirm(plan, location: location) else { return }
            let destination: URL
            switch plan {
            case .inPlace(let url):
                destination = url
                try installer.install(plan)
            case .copy(let source, let url, _, _):
                destination = url
                try await quitInstances(at: url)
                try installer.install(plan)
                do {
                    try AppInstaller.trashSource(source)
                } catch {
                    log.error("could not trash \(source.path, privacy: .public): \(String(describing: error), privacy: .public)")
                }
            }
            log.notice("installed \(destination.path, privacy: .public)")
            try relaunch(at: destination)
        } catch {
            log.error("move failed: \(String(describing: error), privacy: .public)")
            let failure = NSAlert(error: error)
            failure.messageText = "\(name) could not move itself"
            failure.informativeText = """
                \(error.localizedDescription)

                Quit \(name). Move it to the Applications folder with the Finder, then open it again. If macOS asks, allow \(name) in Privacy & Security > App Management.
                """
            NSApp.activate()
            failure.runModal()
        }
    }

    private static func confirm(_ plan: AppInstaller.Plan, location: AppLocation) -> Bool {
        let name = location.appName
        let alert = NSAlert()
        alert.messageText = "Move \(name) to the Applications folder?"
        var button = "Move and Relaunch"
        var reason: String
        if location.isTranslocated {
            reason = "macOS runs a temporary copy of \(name), because the app was not moved with the Finder. macOS hides the icon of this copy with the other items."
        } else if location.canHide {
            alert.messageText = "Relaunch \(name)?"
            reason = "\(name) is now in the Applications folder, but it started somewhere else. macOS hides its icon with the other items."
            button = "Relaunch"
        } else {
            reason = "\(name) is not in the Applications folder, so macOS hides its icon with the other items."
        }
        reason += " Until \(name) runs from the Applications folder, it hides nothing."
        var action = "\(name) can move itself there and open again."
        if case .copy(_, _, let existing?, let incoming) = plan {
            if existing.isNewer(than: incoming) {
                action = "The Applications folder has a newer version of \(name) (\(existing.version ?? "?")). A move replaces it with version \(incoming.version ?? "?")."
                button = "Replace and Relaunch"
            } else {
                action = "\(name) can move itself there and open again. This replaces the copy of \(name) in the Applications folder."
            }
        }
        alert.informativeText = reason + "\n\n" + action
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Quits another instance that runs from the bundle a copy replaces.
    private static func quitInstances(at destination: URL) async throws {
        let others = NSWorkspace.shared.runningApplications.filter { app in
            app != .current && app.bundleURL.map { AppLocation.isSameItem($0, destination) } == true
        }
        others.forEach { $0.terminate() }
        let deadline = ContinuousClock.now + .seconds(5)
        while others.contains(where: { !$0.isTerminated }) {
            guard ContinuousClock.now < deadline else { throw MoveError.stillRunning(destination.path) }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Opens the new copy once this process has quit, so two instances
    /// never hold a restriction at once.
    private static func relaunch(at destination: URL) throws {
        let opener = Process()
        opener.executableURL = URL(fileURLWithPath: "/bin/sh")
        opener.arguments = [
            "-c", #"while kill -0 "$1" 2>/dev/null; do sleep 0.1; done; open "$2""#,
            "sh", String(ProcessInfo.processInfo.processIdentifier), destination.path,
        ]
        try opener.run()
        NSApp.terminate(nil)
    }
}
