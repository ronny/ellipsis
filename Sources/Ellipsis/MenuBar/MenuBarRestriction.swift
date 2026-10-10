import AppKit
import os

enum MenuBarRestrictionError: LocalizedError {
    case frameworkNotLoaded(String)
    case classesNotFound

    var errorDescription: String? {
        switch self {
        case .frameworkNotLoaded(let reason):
            "MenuBarClientCore did not load: \(reason)"
        case .classesNotFound:
            "The MBAssessmentMode classes do not exist in this version of macOS."
        }
    }
}

/// One assessment-mode assertion against `MenuBarAgent`, through the private
/// `MenuBarClientCore` framework. See `docs/spec.md`, "How it hides".
@MainActor
final class MenuBarRestriction {
    private static let log = Logger(subsystem: "au.ronny.Ellipsis", category: "restriction")
    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"

    /// MenuBarAgent takes system items as integer codes. 0–6 match the public
    /// `AEMenuBarItem` constants in order; 8 is Control Center. Codes past the
    /// enum are ignored, so a generous range keeps every allowable item visible.
    private static let allSystemItems = (0...40).map { NSNumber(value: $0) }

    private let configurationClass: NSObject.Type
    private let assertionClass: NSObject.Type
    private var assertion: NSObject?
    /// Callers waiting for the newest assertion to report back.
    private var activationWaiters: [CheckedContinuation<Void, Never>] = []
    private var isActivating = false

    var isActive: Bool { assertion != nil }

    /// Returns once the newest assertion has reported back, or at once if
    /// it already has. MenuBarAgent lays out only after that.
    func waitUntilActivated() async {
        guard isActivating else { return }
        await withCheckedContinuation { activationWaiters.append($0) }
    }

    init() throws {
        guard dlopen(Self.frameworkPath, RTLD_NOW) != nil else {
            throw MenuBarRestrictionError.frameworkNotLoaded(String(cString: dlerror()))
        }
        guard
            let configurationClass = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type,
            let assertionClass = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type
        else {
            throw MenuBarRestrictionError.classesNotFound
        }
        self.configurationClass = configurationClass
        self.assertionClass = assertionClass
    }

    /// Hides the given apps and shows every other running app and every system
    /// item. Replaces any assertion held before. The allow-list is a snapshot of
    /// the running apps, so call this again when an app launches.
    ///
    /// Activation is asynchronous. The newest assertion wins while several are
    /// alive, so the old one stays until the new one reports back. Invalidating
    /// it earlier drops every restriction for a moment and every item flashes.
    func apply(hiddenBundleIdentifiers hidden: Set<String>) {
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let allowed = Set(running).subtracting(hidden).sorted()

        let configuration = (configurationClass as AnyObject)
            .perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
            .perform(NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:"),
                     with: Self.allSystemItems as NSArray, with: allowed as NSArray)?
            .takeUnretainedValue()
        let assertion = assertionClass.init()
        nonisolated(unsafe) let previous = self.assertion
        isActivating = true
        let started = ContinuousClock.now
        let log = Self.log
        log.notice("activating: hiding \(hidden.count) apps, replacing \(previous != nil)")
        let completion: @convention(block) (Any?) -> Void = { [weak self] error in
            let elapsed = ContinuousClock.now - started
            if let error {
                log.error("activation failed after \(elapsed, privacy: .public): \(String(describing: error), privacy: .public)")
            } else {
                log.notice("activated after \(elapsed, privacy: .public)")
            }
            _ = previous?.perform(NSSelectorFromString("invalidate"))
            Task { @MainActor in
                self?.activated(assertion)
            }
        }
        _ = assertion.perform(NSSelectorFromString("activateWithConfiguration:completionHandler:"),
                              with: configuration, with: completion)
        self.assertion = assertion
    }

    private func activated(_ assertion: NSObject) {
        guard assertion === self.assertion else { return }  // an older one; the newest is still on its way
        isActivating = false
        let waiters = activationWaiters
        activationWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }

    func release() {
        Self.log.notice("releasing: active \(self.assertion != nil), activating \(self.isActivating)")
        _ = assertion?.perform(NSSelectorFromString("invalidate"))
        assertion = nil
        isActivating = false
        let waiters = activationWaiters
        activationWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }
}
