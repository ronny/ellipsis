import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sets: HiddenSets
    private let state: AppState
    private let permission = AccessibilityPermission()
    private let updater = Updater()
    private var settingsWindow: SettingsWindow?
    private var menuBar: MenuBarManager?
    private var clockZone: ClockZone?
    private var divider: IconDivider?

    override init() {
        AppState.registerDefaults(hasNotch: NSScreen.screens.contains { $0.safeAreaInsets.top > 0 })
        sets = HiddenSets()
        state = AppState()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let restriction: MenuBarRestriction
        do {
            restriction = try MenuBarRestriction()
        } catch {
            Self.quit(with: error)
            return
        }
        let location = AppLocation.current()
        menuBar = MenuBarManager(
            restriction: restriction, sets: sets, state: state, permission: permission, location: location, updater: updater
        ) { [unowned self] in
            showSettings()
        }
        if location.canHide {
            permission.askAtLaunchIfNeeded()
        } else {
            // After the icon is in the menu bar.
            DispatchQueue.main.async {
                AppMover.offerMove()
            }
        }
        clockZone = ClockZone(state: state, permission: permission)
        divider = IconDivider(state: state, sets: sets, permission: permission) { [weak menuBar] in
            menuBar?.iconFrame
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        divider?.release()
        menuBar?.release()
    }

    private func showSettings() {
        if settingsWindow == nil, let clockZone {
            settingsWindow = SettingsWindow(state: state, sets: sets, permission: permission, clockZone: clockZone, updater: updater)
        }
        settingsWindow?.show()
    }

    private static func quit(with error: Error) {
        let alert = NSAlert()
        alert.messageText = "Ellipsis cannot run on this version of macOS"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        NSApp.activate()
        alert.runModal()
        NSApp.terminate(nil)
    }
}
