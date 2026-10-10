import AppKit
import EllipsisCore
import Observation
import os

/// Owns the Ellipsis icon and the restriction, and keeps the restriction in
/// step with the hidden sets.
@MainActor
@Observable
final class MenuBarManager {
    let sets: HiddenSets
    let state: AppState

    private let restriction: MenuBarRestriction
    private let rehide: RehideMonitor
    private let updater: Updater
    private let permission: AccessibilityPermission
    private let location: AppLocation
    private var floatingBar: FloatingBar?
    /// The app whose item a bar click is opening. While set, and while the
    /// set is shown, the restriction lets that item through: alone among
    /// the hidden apps first, and if it still does not fit, alone of all.
    private var clickThroughTarget: String?
    private var clickThroughHidesEveryOtherApp = false
    private var clickThrough: Task<Void, Never>?
    private var barPlacement: Task<Void, Never>?
    private static let log = Logger(subsystem: "au.ronny.Ellipsis", category: "clickThrough")
    private static let iconLog = Logger(subsystem: "au.ronny.Ellipsis", category: "icon")
    private static let restrictionLog = Logger(subsystem: "au.ronny.Ellipsis", category: "restriction")
    private var iconDebounce = ClickDebounce()
    private let openSettingsHandler: () -> Void
    private let icon = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var launchObserver: Task<Void, Never>?
    private var pointerMonitor: Any?
    private var clockHoverRestore: Task<Void, Never>?
    private var isPointerInClockZone = false

    private static let hiddenImage = ellipsisImage()
    private static let shownImage = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Hide items")?
        .withSymbolConfiguration(.init(pointSize: 15, weight: .bold))

    /// Three 4-point dots, like the Ice control item. SF Symbol `ellipsis`
    /// is too small at menu bar sizes.
    private static func ellipsisImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            NSColor.black.setFill()
            for x in stride(from: 2.0, through: 14.0, by: 6.0) {
                NSBezierPath(ovalIn: NSRect(x: x, y: 8, width: 4, height: 4)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Show hidden items"
        return image
    }

    init(
        restriction: MenuBarRestriction,
        sets: HiddenSets,
        state: AppState,
        permission: AccessibilityPermission,
        location: AppLocation,
        updater: Updater,
        openSettings: @escaping () -> Void
    ) {
        self.restriction = restriction
        self.sets = sets
        self.state = state
        self.permission = permission
        self.location = location
        self.updater = updater
        self.openSettingsHandler = openSettings
        self.rehide = RehideMonitor(state: state, sets: sets)
        rehide.panelFrame = { [weak self] in self?.floatingBar?.frame }

        icon.autosaveName = "ellipsis.icon"
        if let button = icon.button {
            button.target = self
            button.action = #selector(iconClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        applyCurrentState()
        observeChanges()
        installClockHover()

        // A newly launched app is not in the allow-list snapshot, so it would hide.
        launchObserver = Task { [weak self] in
            for await _ in NSWorkspace.runningApplicationChanges() {
                guard let self, restriction.isActive else { continue }
                self.applyCurrentState()
            }
        }
    }

    /// The icon's window frame in screen coordinates, for the divider.
    var iconFrame: NSRect? { icon.button?.window?.frame }

    // MARK: Show and hide

    /// A normal click toggles the hidden set. An Option click toggles both sets.
    func toggle(includingAlwaysHidden: Bool) {
        let isShown = includingAlwaysHidden ? sets.isAlwaysHiddenSetShown : sets.isHiddenSetShown
        if isShown {
            hide()
        } else {
            show(includingAlwaysHidden: includingAlwaysHidden)
        }
    }

    func show(includingAlwaysHidden: Bool) {
        sets.show(includingAlwaysHidden: includingAlwaysHidden)
    }

    func hide() {
        sets.hide()
    }

    func applyCurrentState() {
        let inBar = state.hiddenItemsPlacement == .floatingBar
        if !sets.isHiddenSetShown {
            clickThroughTarget = nil
        }
        var hidden: Set<String>
        if inBar {
            // The bar shows the set; the menu bar keeps hiding it.
            hidden = sets.hidden.union(state.isAlwaysHiddenEnabled ? sets.alwaysHidden : [])
        } else {
            hidden = sets.identifiersToHide(isAlwaysHiddenEnabled: state.isAlwaysHiddenEnabled)
        }
        if let target = clickThroughTarget {
            if clickThroughHidesEveryOtherApp {
                // The apps a picker lists. A list that also names background
                // processes is ignored by MenuBarAgent as a whole.
                let running = NSWorkspace.shared.runningApplications
                    .filter { [.regular, .accessory].contains($0.activationPolicy) }
                    .compactMap(\.bundleIdentifier)
                hidden = Set(running).subtracting([target, Bundle.main.bundleIdentifier ?? ""])
            } else {
                hidden.remove(target)
            }
        }
        hidden = location.identifiersToHide(hidden, own: Bundle.main.bundleIdentifier)
        Self.restrictionLog.notice(
            "apply: shown \(self.sets.isHiddenSetShown), always-hidden shown \(self.sets.isAlwaysHiddenSetShown), hiding \(hidden.count) apps, click-through \(self.clickThroughTarget != nil)"
        )
        if hidden.isEmpty {
            restriction.release()
        } else {
            restriction.apply(hiddenBundleIdentifiers: hidden)
        }
        icon.button?.image = sets.isHiddenSetShown ? Self.shownImage : Self.hiddenImage
        updateFloatingBar(inBar: inBar)

        // Arm once per show, not on every reapply, so the timeout is not reset
        // by unrelated changes such as the clock hover.
        if sets.isHiddenSetShown {
            if !rehide.isArmed {
                rehide.arm()
            }
        } else {
            rehide.disarm()
        }
    }

    func release() {
        rehide.disarm()
        clickThrough?.cancel()
        barPlacement?.cancel()
        floatingBar?.hide()
        launchObserver?.cancel()
        clockHoverRestore?.cancel()
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
        }
        restriction.release()
    }

    /// Reapplies the restriction whenever a set or a related setting changes,
    /// from any caller. `onChange` fires once per registration, before the
    /// write lands, so it hops to the next run-loop turn and re-registers.
    private func observeChanges() {
        withObservationTracking {
            _ = sets.hidden
            _ = sets.alwaysHidden
            _ = sets.isHiddenSetShown
            _ = sets.isAlwaysHiddenSetShown
            _ = state.isAlwaysHiddenEnabled
            _ = state.hiddenItemsPlacement
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applyCurrentState()
                self.observeChanges()
            }
        }
    }

    // MARK: The floating bar

    private func updateFloatingBar(inBar: Bool) {
        guard inBar, sets.isHiddenSetShown, clickThroughTarget == nil, location.canHide else {
            floatingBar?.hide()
            return
        }
        if floatingBar == nil {
            floatingBar = FloatingBar { [weak self] id in
                self?.barClicked(id)
            }
        }
        var shown = sets.hidden
        if sets.isAlwaysHiddenSetShown {
            shown.formUnion(sets.alwaysHidden)
        }
        let screen = icon.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        floatingBar?.show(
            apps: FloatingBar.apps(for: shown),
            hint: permission.isTrusted ? nil : "with the Accessibility permission, one click opens its menu bar item",
            iconFrame: iconFrame,
            screen: screen
        )
        // The icon can move once MenuBarAgent lays out the new restriction;
        // the bar follows it.
        barPlacement?.cancel()
        barPlacement = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, let bar = floatingBar, bar.isVisible else { return }
            bar.place(iconFrame: iconFrame, screen: icon.button?.window?.screen ?? screen)
        }
    }

    /// Click-through, spec F8. With the Accessibility permission the item
    /// is let through on its own; if the layout shows it collapsed, every
    /// other app hides so it fits. It is then pressed, and the normal
    /// restriction returns once its menu closes. Without the permission
    /// nothing can be read, so every other app hides at once, and the item
    /// stays for the user to click, until a rehide or the icon.
    private func barClicked(_ id: String) {
        Self.log.info("bar click on \(id, privacy: .public); trusted: \(self.permission.isTrusted)")
        clickThrough?.cancel()
        clickThroughTarget = id
        clickThroughHidesEveryOtherApp = !permission.isTrusted
        applyCurrentState()
        guard permission.isTrusted else { return }
        clickThrough = Task { [weak self] in
            // The item is pressed the moment it is drawn: the element is the
            // app's button, wherever the animation has it. MenuBarAgent
            // animates a new layout for about a second, and mid-way the
            // item can overlap a neighbour, so it counts as collapsed only
            // once its frame holds still between two reads. Collapsed: hide
            // every other app and go on waiting.
            var pressed = false
            var lastFrame: CGRect?
            let deadline = ContinuousClock.now + .seconds(4)
            while ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, let self else { return }
                let layout = await Task.detached(priority: .userInitiated) { MenuBarLayout.read() }.value
                if let drawn = layout?.drawnItem(of: id), let element = drawn.element {
                    pressed = await Task.detached(priority: .userInitiated) { element.press() }.value
                    Self.log.info("pressed \(id, privacy: .public) at \(Int(drawn.frame.minX)): \(pressed)")
                    break
                }
                let item = layout?.displays.lazy.flatMap(\.items).first { $0.bundleIdentifier == id }
                let collapsed = item != nil && item?.frame == lastFrame
                lastFrame = item?.frame
                guard collapsed, let item, !self.clickThroughHidesEveryOtherApp else { continue }
                Self.log.info("\(id, privacy: .public) is collapsed at \(Int(item.frame.minX)); hiding every other app")
                self.clickThroughHidesEveryOtherApp = true
                self.applyCurrentState()
                lastFrame = nil
            }
            guard !Task.isCancelled, let self else { return }
            if pressed {
                // Let the menu open, then wait for it to close.
                try? await Task.sleep(for: .milliseconds(300))
                while !Task.isCancelled, RehidePolicy.isMenuOpen(MenuBarGeometry.openMenuFrames(), menuBar: .current) {
                    try? await Task.sleep(for: .milliseconds(300))
                }
                guard !Task.isCancelled else { return }
            }
            self.clickThroughTarget = nil
            self.hide()
            self.applyCurrentState()
        }
    }

    // MARK: Clock hover

    /// Notification Center does not open from a clock click while a
    /// restriction is active, and MenuBarAgent decides that at mouse-down.
    /// So the restriction lifts while the pointer is in the trailing zone of
    /// the menu bar and returns shortly after it leaves. `ClockZone` sizes
    /// the zone.
    private func installClockHover() {
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            let point = NSEvent.mouseLocation
            Task { @MainActor in
                self?.pointerMoved(to: point)
            }
        }
    }

    private func pointerMoved(to point: NSPoint) {
        let inZone = MenuBarGeometry.current.clockZoneContains(point, width: state.clockZoneWidth)
        guard inZone != isPointerInClockZone else { return }
        isPointerInClockZone = inZone
        clockHoverRestore?.cancel()
        Self.restrictionLog.notice("pointer \(inZone ? "entered" : "left") the clock zone")
        if inZone {
            restriction.release()
        } else {
            clockHoverRestore = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                self?.applyCurrentState()
            }
        }
    }

    // MARK: Icon clicks

    @objc private func iconClicked() {
        // On macOS 27 the event that reaches the action carries no modifier
        // flags, so read the keyboard state directly.
        let flags = NSEvent.modifierFlags
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
        guard iconDebounce.accept(at: ProcessInfo.processInfo.systemUptime) else {
            Self.iconLog.notice("dropped a duplicate icon action")
            return
        }
        Self.iconLog.notice(
            "icon clicked: right \(isRightClick), option \(flags.contains(.option)), control \(flags.contains(.control)), shown \(self.sets.isHiddenSetShown)"
        )
        if isRightClick || flags.contains(.control) {
            showMenu()
        } else if !location.canHide {
            AppMover.offerMove(location)
        } else {
            toggle(includingAlwaysHidden: flags.contains(.option))
        }
    }

    /// A status item with a `menu` opens it on every click, so the menu is
    /// attached only for the duration of one click.
    private func showMenu() {
        let menu = NSMenu()

        let alwaysHidden = NSMenuItem(
            title: "Show always-hidden items",
            action: #selector(toggleAlwaysHiddenShown),
            keyEquivalent: ""
        )
        alwaysHidden.target = self
        alwaysHidden.state = sets.isAlwaysHiddenSetShown ? .on : .off
        alwaysHidden.isEnabled = state.isAlwaysHiddenEnabled
        menu.addItem(alwaysHidden)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let update = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        update.isEnabled = updater.canCheckForUpdates
        menu.addItem(update)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Ellipsis", action: #selector(NSApplication.terminate), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        icon.menu = menu
        icon.button?.performClick(nil)
        icon.menu = nil
    }

    @objc private func toggleAlwaysHiddenShown() {
        show(includingAlwaysHidden: !sets.isAlwaysHiddenSetShown)
    }

    @objc private func openSettings() {
        openSettingsHandler()
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }
}
