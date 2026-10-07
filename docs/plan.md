# Ellipsis — implementation plan

Each phase ends with a jj change that builds and runs.

## Phase 0: Spike — done

See `docs/phase0.md`. The large-length method failed. The assessment-mode restriction works. The spike in `Sources/Ellipsis/main.swift` shows one icon. A click toggles a restriction that hides the bundle identifiers in the `hiddenBundleIdentifiers` user default.

Deliverables: `Package.swift`, `Sources/Ellipsis/main.swift`, `scripts/bundle.sh`, `Resources/Info.plist`, `docs/phase0.md`.

## Phase 1: App skeleton — done

1. Replace `main.swift` with `EllipsisApp.swift` (`@main`, SwiftUI `App`) and an `AppDelegate` via `NSApplicationDelegateAdaptor`.
2. Add a `Settings` scene with an empty view.
3. Add `MenuBarRestriction`: a wrapper around the private `MBAssessmentMode*` classes. It loads `MenuBarClientCore` with `dlopen`, resolves the classes, and exposes `apply(hiddenBundleIdentifiers:)` and `release()`. It holds one assertion at a time. It reports an error if the classes do not exist.
4. Add `MenuBarManager` (`@MainActor`, `@Observable`). It owns the `NSStatusItem` for the icon and the `MenuBarRestriction`.
5. Add `HiddenSets`: the hidden set, the always-hidden set, and `isHiddenSetShown`, persisted in `UserDefaults`.
6. Add `AppState` for the other settings, backed by `UserDefaults` through `@AppStorage` keys.
7. At launch, if the private classes do not exist, show an alert and quit.
8. `scripts/run.sh`: bundle, copy to `/Applications`, launch. A debug build is `EllipsisDev.app` with the identifier `au.ronny.EllipsisDev`, so it runs next to a release build with its own settings. `MenuBarAgent` only matches apps in `/Applications` (see `docs/phase0.md`).

Exit criteria: the app runs, shows the icon, and applies the persisted sets at launch.

## Phase 2: F1 and F2 — hide, show, always-hidden — done

1. Implement `MenuBarManager.toggle()`. Hidden: restriction hides both sets. Shown: restriction hides only the always-hidden set. Shown with Option: no restriction.
2. Icon image switches between `…` and `‹`. Use SF Symbols `ellipsis` and `chevron.left`. Ice is GPL-3, so its Ellipsis asset stays out of this repository.
3. Persist `isHiddenSetShown` and restore it at launch.
4. Right-click on the icon opens an `NSMenu` with "Show always-hidden items", "Settings…", "Quit".
5. Setting: always-hidden set on or off. Off means the always-hidden set is never hidden. `MenuBarManager` observes the sets and this setting with `withObservationTracking`, so any writer, including the Settings window, changes the restriction at once.
6. Release the restriction on quit (`applicationWillTerminate`).
7. Clock click under a restriction fails (acceptance criterion 8), and `MenuBarAgent` decides at mouse-down, so a release on mouse-down is too late. A global mouse-move monitor releases the restriction while the pointer is in the trailing zone of the menu bar, 300 points until Phase 6 sizes it.

Exit criteria: acceptance criteria 2, 3, 4, 8 and 9 pass. Checklist in `docs/testing.md`.

## Phase 3: F3 — auto-rehide — done

1. `RehideMonitor`: armed when the hidden set becomes shown, disarmed when it hides. A timer `Task` sleeps for the timeout, then hides. A settings change while armed reinstalls the monitors.
2. Click outside: `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown])`. A click in the menu bar or inside an open menu does not hide. Works with no Accessibility permission.
3. Focus change: `NSWorkspace.didActivateApplicationNotification` (not for Ellipsis itself) and `activeSpaceDidChangeNotification`.
4. Menu-open guard: `NSMenu.didBeginTrackingNotification` only fires for menus in the Ellipsis process, so other apps' status item menus are found with `CGWindowListCopyWindowInfo`. A window at the pop-up menu level whose top edge touches the menu bar is an open menu. Deprecated since macOS 14 but needs no permission, unlike `SCShareableContent`. A hide that finds a menu open retries every 300 ms.
5. `RehidePolicy` holds the pure decisions, with tests. `MenuBarGeometry` holds the menu bar frames and the clock zone.
6. Settings: three switches and the timeout stepper.

Exit criteria: acceptance criteria 5, 6 and 7 pass.

## Phase 4: F4 — Settings window — done

1. `SettingsView` is a `TabView`: General (launch at login, rehide switches, timeout stepper, About), Hidden (app picker), Always Hidden (the enable switch and an app picker).
2. `RunningApps`: the running apps from `NSWorkspace.shared.runningApplications` with a `.regular` or `.accessory` activation policy, minus Ellipsis. Refreshes on `didLaunchApplicationNotification` and `didTerminateApplicationNotification`. An app in a set that is not running stays listed, with its name and icon from LaunchServices, so the user can uncheck it.
3. `AppPicker`: rows for a `Form` section, one checkbox per app with icon and name. An app can be in one set only: a check in one set removes the app from the other. The row shows which set holds the app.
4. `LaunchAtLogin` wraps `SMAppService.mainApp`. The service status is the source of truth. `requiresApproval` shows a button that opens Login Items in System Settings.
5. About section: version from `Bundle.main`, quit button.
6. The right-click menu opens the window and activates the app (Phase 2).

Exit criteria: every control changes behavior at once, no restart. `MenuBarManager` observes the sets and `AppState`, so a checkbox changes the restriction on the spot.

## Phase 5: Release pipeline — done

1. App icon: `scripts/make-icon-art.swift` draws `Resources/AppIcon.png` (three dots on a dark rounded square). `scripts/make-icon.sh` turns it into `Resources/AppIcon.icns` with `sips` and `iconutil`. Both files are committed.
2. `Resources/Ellipsis.entitlements`: hardened runtime, no sandbox, no entitlements. `MenuBarClientCore` is Apple-signed, so library validation permits the `dlopen`. Tested: the hardened build hides items.
3. `scripts/sign.sh`: `codesign --force --options runtime --timestamp`. `DEVELOPER_ID` names the identity; default is the one Developer ID Application identity in the keychain; more than one is refused. A revoked certificate is refused.
4. `scripts/notarize.sh`: `notarytool submit --wait`, `stapler staple`, `stapler validate`, `spctl --assess`. `NOTARY_PROFILE` names the keychain profile; default `ellipsis`.
5. `scripts/release.sh X.Y.Z`: bundle a release build with `VERSION` and `BUILD` (the commit count), sign, notarize, zip with `ditto` to `build/Ellipsis-X.Y.Z.zip`.
6. `README.md`: install, build and release instructions, the private-API risk and the Focus limit.

Exit criteria: acceptance criteria 1, 10 and 11 pass on a clean checkout.

## Phase 5b: Optional Accessibility permission — done

`AccessibilityPermission` (trust state, opt-out flag, the explanation dialog) and an `AXExtrasMenuBar` scan in `RunningApps` that filters the pickers. The scan runs off the main thread with a 0.2 s timeout per app: an unresponsive app must not block Settings. Spec F6.

## Phase 6: Polish (optional)

- Position-based sets — done, with the icon as the divider (spec F7). The plan was a file panel for the `MenuBarAgent` layout table, which needs Full Disk Access or a one-time pick. `MenuBarLayout` (Accessibility, see the clock zone below) gives the visible items and their owners with no file, so that is used instead. A first version had a separate divider item; the icon does the same job with one item fewer, as in Ice and Bartender. `IconDivider` reads the layout after a Cmd-drag (a mouse-up with Cmd held: the global monitor for other apps' items, a local one for the icon itself), after a launch, and when the set is shown. `DividerPolicy` holds the set arithmetic, with tests. Only visible items are readable, so a hidden app keeps its membership until the set is shown.
- Clock zone calibration — done. `MenuBarLayout` reads the windows of `MenuBarAgent` over Accessibility: one slot per item with its frame and owner pid, and `com.apple.menuextra.clock` for the clock. `ClockZone` sets `clockZoneWidth` to the clock offset plus a 30-point margin at launch, when the permission arrives, and when Settings opens. Without the permission, "Click the Clock…" in General takes the width from one click on the clock's left edge. Measured with synthetic clicks: a 1-point zone never opens Notification Center, a 40-point zone (2 points of margin) opens it from a 10,000 points/s approach.
- Export and import settings — done. "Export…" and "Import…" buttons in General. `SettingsFile` writes the settings keys (not the shown state, not the Accessibility opt-out) to a plist through `NSSavePanel`, and reads one back through `NSOpenPanel`. Import checks each known key's type, ignores unknown keys, and writes key by key so AppKit's own keys in the domain stay. `AppState` and `HiddenSets` reload from the store afterwards.
- Updates — done, with Sparkle 2 from SwiftPM. `Updater` wraps `SPUStandardUpdaterController` for the "Check for Updates…" menu item and the About section in General. `bundle.sh` copies `Sparkle.framework` into `Contents/Frameworks`, `sign-sparkle.sh` signs its XPC services and helpers for notarization, and `release.sh` writes `build/appcast.xml` with `generate_appcast`. `publish.sh` uploads the zip and the appcast to the GitHub release, and `SUFeedURL` reads the appcast from `releases/latest/download/`, so no other host is necessary. A debug build never checks on its own (`SUEnableAutomaticChecks` is false), so it does not replace itself with a release.

## Phase 7: VM test framework

The acceptance criteria are tested by hand, on the developer's own menu bar. That blocks the desktop while a test runs, an agent cannot run them, and the record of a pass is a word in `docs/testing.md`. This phase runs the app in a macOS virtual machine and drives it from a test target. There is no macOS simulator; the VM is the substitute. Notch behavior is out of scope: a virtual display has no notch (Phase 8).

The VM is a [Tart](https://tart.run) guest, cloned from `ghcr.io/cirruslabs/macos-golden-gate-base` (macOS 27, `admin`/`admin`, auto-login, sshd, VNC, Gatekeeper off, SIP on). The host builds everything. The guest gets the app, the fixture app and the probe over `scp`, and runs them over `ssh`. `tart clone` is an APFS clone, so one clone per test run is cheap and every run starts from the same state.

1. Spike — done. Every answer is yes: a process under `sshd` posts `CGEvent`s to the auto-login session, the image grants Accessibility to `sshd-keygen-wrapper` so nothing is granted by hand, a restriction hides an app in the guest, and `screencapture` returns the screen. `docs/phase7.md` has the record. The Homebrew formula for `tart` is broken on current Homebrew (`depends_on :macos`); the release tarball from GitHub installs as `~/.local/bin/tart`.
2. Golden VM — done. `scripts/vm.sh prepare` clones the base image as `ellipsis-golden`, boots it, puts the key `~/.tart/ellipsis_ed25519` in it, and shuts it down. 20 seconds, no hand. `scripts/vm.sh` also has `clone` (from the golden VM, headless, prints the IP once `ssh` answers; 20 seconds), `ip`, `ssh`, `scp`, `stop` and `delete`. The VM name comes from `ELLIPSIS_VM`, default `ellipsis-test`.
3. Fixture app — done. `Sources/Fixture/main.swift`: one status item with a menu. Its title and bundle identifier come from `Info.plist`, so `scripts/bundle-fixture.sh N` writes `FixtureN.app` with `au.ronny.EllipsisFixture.N`. Tests need apps that own menu bar items with known identifiers, and a guest has none. "Mark" in the item's menu writes `~/au.ronny.EllipsisFixture.N.marked`, so a test can see that a click reached the app's menu.
4. Probe — done. `Sources/Probe/main.swift`, an executable target with no UI. Subcommands: `layout` (`MenuBarLayout.read()` as JSON), `menus` (`MenuBarGeometry.openMenuFrames()`), `screens` (frame and safe area top of each screen), `move X Y`, `click X Y [--option] [--command] [--right]` and `drag X1 Y1 X2 Y2 [--command]` (`CGEvent`s at a point in Accessibility coordinates). `MenuBarLayout` and `MenuBarGeometry` moved to a library target `EllipsisCore` that `Ellipsis`, `Probe` and the tests link, and `MenuBarLayout` is `Codable`, so the tests decode the probe's output into the same type. The probe is the only thing that touches the guest's screen.
5. Test target — done. `Tests/EllipsisVMTests`, swift-testing, on the host. `Guest` wraps `scripts/vm.sh ssh`: `run`, `probe` decoded from JSON, `launch`, `quit`, `kill`, `launchEllipsis(settings)` (quit, `defaults delete`, `defaults write` each setting plus the ones a test needs to run unattended, launch, wait for the icon), `items`, `appItems`, `iconFrame`, `clickIcon(option:)`, `openMenus`, `screenshot`, `waitUntil` and `expectStable` with polling, since `MenuBarAgent` lays out after the event. `startFixtures` puts the guest in the same state before every test. Every suite has `.enabled(if: Guest.isConfigured)`, so `mise run test` skips them, and `.serialized`, since there is one menu bar.
6. Test run — done. `scripts/vm-test.sh`: build, bundle the app, three fixtures and the probe, `vm.sh clone`, copy the bundles to `/Applications` and the probe to the home directory, `swift test --filter EllipsisVMTests`, copy `~/screenshots` out to `build/vm-screenshots`, `vm.sh delete`. `mise run vm-test` runs it: 46 seconds for the first suite, 22 of them tests. `ELLIPSIS_VM_KEEP` leaves the VM running; `ELLIPSIS_VM_REUSE` runs against a VM that is already up, which is the loop while writing a test. The ssh control socket in `vm.sh` makes each guest command cost about 40 ms.
7. Settings — done. Tests write them with `defaults write au.ronny.EllipsisDev` before the launch, not through the Settings window; each test launches the app with the settings it needs. `AppState` does not see a `defaults write` while the app runs, so row 5a (a timeout change while shown) stays manual.
8. Tests — done. `HideShowTests` (2, 3, 4, 4b, 9, 9a), `RehideTests` (5, 5b, 6, 6a, 6b, 7, 7a), `ClockZoneTests` (8, 8b) and `DividerTests` (D1 to D5): 21 tests, 85 seconds. Two things the tests had to learn about `MenuBarAgent`: it remembers each item's position in its layout table (`docs/phase0.md`) across launches, so `Guest` writes the icon's position before every launch and puts the fixtures back after a drag; and a new item appears first, then moves to its remembered place, so `launchEllipsis` waits for two equal reads. Rows that stay manual, with the reason in the checklist: 1 to 1b (the permission dialog), 4a and 6c (the right-click menu), 5a, 8a and S1 to S9 (the Settings window), 10 and 11 (release scripts). The tests found one bug: `NSWorkspace.didLaunchApplicationNotification` is not posted for `LSUIElement` apps, so the divider never read the menu bar after a menu bar app launched, and the Settings pickers never refreshed for one. Both now watch `NSWorkspace.runningApplications`.
9. CI — dropped. GitHub's hosted macOS runners cannot run a VM, and a self-hosted runner costs a Mac. The VM tests are local: `mise run vm-test`. `mise run test` skips them.
10. Docs — done. `docs/development.md` ("VM tests"), `docs/testing.md` (rows marked `vm`), this file.

Exit criteria — met: `mise run vm-test` passes on a clean checkout with the golden VM present, with no pointer or menu bar change on the host. Every row it covers is marked in `docs/testing.md`.

## Phase 8: F8 — the floating bar

Displays with a notch drop the shown items that do not fit. Spec F8. The bar works on every display, so every step but the spike is built on the desktop and tested in the VM (Phase 7). A virtual display has no notch, but the same drop happens when the status item region ends at the front app's menus: a narrow VM display (`tart set --display`) and a fixture with a wide menu bar reproduce it. `NSScreen.safeAreaInsets` stays zero in the VM, so the placement default takes the insets as a parameter and has a unit test.

1. Spike — done in the VM, host check pending. `docs/phase8.md`. macOS 27 collapses the items that do not fit behind a system `«` button and the Ellipsis icon collapses first. `MenuBarLayout` reports collapsed items with stacked frames. What the host has to answer: whether a notch region behaves like the app-menu region, whether `«` opens with a real mouse, and `NSScreen.safeAreaInsets` on that display.
2. `AppState.hiddenItemsPlacement` — done. `menuBar` or `floatingBar`, the "Show hidden items" picker in General, and a key in the settings file. The default is registered, not written: `registerDefaults(hasNotch:)` picks the bar when a screen has a notch at launch, so a user who never chose follows the display.
3. `FloatingBarPlacement` — done, with unit tests. Right edge under the icon's right edge, top just below the menu bar, kept on screen; the screen's right edge when the icon has no frame.
4. `FloatingBar` — done. A non-activating borderless `NSPanel` at the status bar level, on every Space, with an `NSHostingView`: 18-point app icons, tooltips, hover. Only running apps in the set are listed. The bar moves again 400 ms after it opens, since the icon can move once `MenuBarAgent` lays out.
5. `MenuBarManager` — done. In bar mode a shown set keeps the restriction and opens the bar; an Option show adds the always-hidden set to the bar. `RehidePolicy.shouldHide` takes the panel frame and treats a click in it as inside; `RehideMonitor.panelFrame` supplies it. The clock zone still lifts the restriction while the pointer is in it, which in bar mode shows the items in the menu bar and the bar at once; the measured zone keeps that to the clock.
6. Click-through — done. `MenuBarLayout.Item.element` keeps the owner `AXUIElement` behind `AccessibilityElement`, `@unchecked Sendable`, not encoded, with `press()`. `barClicked` sets `clickThroughTarget`, and `applyCurrentState` then lets that app through the restriction. With the permission, a loop reads the layout every 300 ms for up to 4 s and acts once the item's frame holds still between two reads, since `MenuBarAgent` animates a new layout for about a second: drawn, it is pressed; collapsed (`MenuBarLayout.drawnItem` sees it overlapping another item), every other regular or accessory app hides and the loop goes on. A list that also names background processes is ignored by `MenuBarAgent` as a whole. After the press: wait 300 ms, poll `openMenuFrames` every 300 ms until no menu is open, then hide and apply the normal restriction. `Logger` category `clickThrough` in subsystem `au.ronny.Ellipsis` records each decision.
7. Without the permission — done. The click applies the single-app restriction and closes the bar; the set stays shown, so the rehide conditions and the icon end it. The tooltip says what the permission adds.
8. Docs — done. README, `docs/testing.md` (F1 to F6), spec F8 (collapse, not "not drawn"; the default follows the display), this file.
9. VM tests — done. `FloatingBarTests`, seven tests: a short region collapses items in menu bar mode (the `«` button appears); bar mode shows every app and nothing collapses, with the bar under the icon; an Option show adds the always-hidden set; each rehide condition closes the bar; a click in the bar is not outside; a click on an app without the permission leaves that item alone in the menu bar; a click with the permission opens the app's menu and the normal restriction returns after it closes. `FixtureW` (`scripts/bundle-fixture.sh W 7`, about 240 points) is the short region and `FixtureV` (nine menus, about 113) the one with no room for the front app's own item next to a shown one; a click on A there hides the others only because it must. The no-permission test runs only in a guest without the grant. Bugs the tests found on the way: `MenuBarManager` reapplied the restriction only for regular apps that launched (`didLaunchApplicationNotification` again); the clock zone's 300-point default covers the icon on a 1024-point display. On a fresh guest (2026-09-18) a lone collapsed item passed as drawn: nothing stacks on it, so `drawnItem` now also reads the `«` button into the layout and counts an item left of it as collapsed.
10. Host check — done on the notch MacBook (2026-09-18). The bar is the default at first launch, hangs from the icon, and a click on an app opens its menu with the other items in place. Not checked: whether the notch collapses items behind `«` in menu bar mode, and whether `«` opens with a real mouse.

Exit criteria — met: on the laptop, a click on the icon shows every hidden app in the bar, a click on an app in the bar opens its menu, and the bar closes on each rehide condition.

## File layout

```
Package.swift
Sources/EllipsisCore/
  MenuBarLayout.swift
  MenuBarGeometry.swift
Sources/Fixture/
  main.swift
Sources/Probe/
  main.swift
Sources/Ellipsis/
  EllipsisApp.swift
  AppDelegate.swift
  AppState.swift
  RunningApplicationChanges.swift
  Accessibility/
    AccessibilityPermission.swift
  MenuBar/
    MenuBarManager.swift
    MenuBarRestriction.swift
    HiddenSets.swift
    RehideMonitor.swift
    RehidePolicy.swift
    IconDivider.swift
    DividerPolicy.swift
    ClockZone.swift
    FloatingBar.swift
    FloatingBarPlacement.swift
  Settings/
    SettingsWindow.swift
    SettingsView.swift
    AppPicker.swift
    RunningApps.swift
    LaunchAtLogin.swift
Tests/EllipsisTests/
Tests/EllipsisVMTests/
  Guest.swift
  HideShowTests.swift
  RehideTests.swift
  ClockZoneTests.swift
  DividerTests.swift
  FloatingBarTests.swift
Resources/
  Info.plist
  Fixture-Info.plist
  Ellipsis.entitlements
  AppIcon.png
  AppIcon.icns
scripts/
  bundle.sh
  run.sh
  make-icon-art.swift
  make-icon.sh
  sign.sh
  notarize.sh
  release.sh
  bundle-fixture.sh
  vm.sh
  vm-test.sh
docs/
  spec.md
  plan.md
  phase0.md
  phase7.md
  phase8.md
```

## Testing

- Unit tests for `HiddenSets` (which bundle identifiers a state produces), `AppState` defaults, and `RehidePolicy` (pure functions: "given this click, these menus and this frame, hide or not").
- VM tests for the acceptance criteria that a guest can run (Phase 7). `mise run vm-test`.
- Manual tests for the rest. The checklist in `docs/testing.md` says which rows have a VM test.
- `MenuBarRestriction` talks to `MenuBarAgent`. Do not mock it. Test it by hand.
