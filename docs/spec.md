# Ellipsis — specification

Ellipsis is a macOS menu bar item manager. It hides and shows menu bar items of other apps. It is a stripped-down version of [Ice](https://github.com/jordanbaird/Ice) and [Bartender](https://www.macbartender.com) for macOS 27 (Golden Gate).

## Goals

- Hide and show menu bar items with one click.
- Keep an "always hidden" set of apps that you never want to see.
- Rehide the items automatically after a timeout or after a click outside the menu bar.
- Need no permission to hide and show. No Screen Recording, no Full Disk Access. Accessibility is optional (see F6).
- Build with SwiftPM and shell scripts only. No `.xcodeproj`, no Xcode GUI.
- Ship a Developer ID signed and notarized `.app`.

## Non-goals

- Menu bar appearance changes (tint, shadow, border, shape).
- Menu bar item search or spotlight.
- Custom icons or profiles.
- Per-display rules.
- Global hotkeys (not in v1).
- Item rearrangement. Ellipsis never moves an item.
- Hiding one item of an app while another item of the same app stays visible. macOS 27 cannot do this (see "How it hides").
- macOS 26 or earlier.

## Definitions

| Term | Meaning |
|---|---|
| Item | One menu bar item from any app. |
| App | The owner of one or more items, identified by its bundle identifier. |
| Hidden set | Apps that Ellipsis hides until you click the Ellipsis icon. |
| Always-hidden set | Apps that Ellipsis hides until you Option+click the Ellipsis icon. |
| Restriction | The macOS 27 assessment-mode allow-list that Ellipsis holds while it hides apps. |
| Ellipsis icon | The clickable `NSStatusItem` that Ellipsis owns. Shows `…` or `‹`. |

## How it hides

macOS 27 moved menu bar layout into a system process, `MenuBarAgent`. The old method, a status item with a length of 10,000 points, no longer works. `MenuBarAgent` places a wide item only while it fits. It draws items that do not fit on top of the wide item. It never pushes an item off-screen. The Phase 0 spike proved this on a display without a notch. See `docs/phase0.md`.

Ellipsis uses the menu bar half of macOS assessment mode instead. This is the mechanism behind `AEAssessmentConfiguration.allowedMenuBarItems` (public, macOS 27). The public API needs an Apple-approved entitlement and locks the whole machine. The private framework `MenuBarClientCore` exposes only the menu bar part:

```
MBAssessmentModeConfiguration(allowedSystemItems: [NSNumber], allowedBundleIdentifiers: [String])
MBAssessmentModeAssertion.activate(withConfiguration:completionHandler:)
MBAssessmentModeAssertion.invalidate()
```

While an assertion is active, `MenuBarAgent` shows only the apps and system items in the allow-list. Ellipsis puts every app except the hidden ones in the allow-list. Ellipsis puts every system item code (integers 0 to 40) in the allow-list. No permission is necessary. Thaw 3 uses the same mechanism.

Known limits of this mechanism:

- Granularity is one app, not one item. If an app has two items, both hide together.
- Focus and the camera/microphone indicator are hidden while a restriction is active. No system item code brings them back.
- The framework is private. Ellipsis loads it with `dlopen` and checks that the classes exist at launch. If they do not exist, Ellipsis shows an alert and quits.
- The `allowedSystemItems` codes are undocumented. Code 2 is the clock, code 6 is Wi-Fi, code 8 is Control Center.
- Notification Center does not open from a clock click while a restriction is active. Control Center and Wi-Fi menus do open. No system item code changes this (tested 0 to 2000). `MenuBarAgent` decides at mouse-down, so a release on mouse-down is too late. Ellipsis releases the restriction while the pointer is in the trailing zone of the menu bar, and applies it again 0.5 seconds after the pointer leaves. Hidden items show while the pointer is there. The zone is 300 points by default, the clock plus 30 points when measured (F6), or set by one click on the clock (F4).
- Item frames are not readable without the Accessibility permission. `MenuBarAgent` has a utilities service (`listMenuBarItemsForSpaceID:`, `getPreferredTrailingItemPositions:`) but it needs the private entitlement `com.apple.private.menubar.utilities`. The window server exposes no window per item. With the permission, the windows of `MenuBarAgent` expose one slot per item with its frame and owner.
- Activation is asynchronous. The newest assertion wins while several are alive, and an `invalidate` of an older one leaves the newer one intact. Ellipsis keeps the old assertion until the new one reports back, or every item flashes for a moment.
- `MenuBarAgent` matches the allow-list only against apps that run from `/Applications`. An app that runs from another folder is always hidden while a restriction is active. This includes Ellipsis itself. The Ellipsis icon disappears if Ellipsis runs from a build folder. App Translocation has the same result: macOS runs a quarantined app that the Finder did not move from a temporary folder, even when the app is in `/Applications`. So Ellipsis holds no restriction unless it runs from the top level of `/Applications` and is not translocated (`AppLocation`). At launch, and at a click on the icon, it offers to move itself there and relaunch. Ellipsis also never puts its own bundle identifier in a restriction, whatever the sets say.

Ellipsis releases the restriction when it shows the hidden set. Ellipsis holds a restriction that hides only the always-hidden set when it shows the hidden set with a normal click.

## Features

### F1: Hide and show the hidden set

- The Ellipsis icon shows `…` when the hidden set is hidden. It shows `‹` when the set is shown.
- Click the icon to toggle the hidden set.
- The state persists across restarts.

### F2: Always-hidden set

- Apps in the always-hidden set stay hidden after a normal click.
- Option+click on the Ellipsis icon shows both sets.
- The Settings window has a switch to enable or disable this set. Default: enabled.

### F3: Auto-rehide

Ellipsis rehides the hidden set when one of these conditions is true and the related setting is on:

- Timeout. A timer starts when the set is shown. Default: 15 seconds. Range: 1–300 seconds. Off is permitted.
- Click outside. The user clicks anywhere that is not the menu bar.
- Focus change. The frontmost app changes or the active Space changes.

Each condition has its own switch in Settings. Defaults: timeout on, click outside on, focus change off.

Ellipsis does not rehide while a menu from a shown item is open.

### F4: Settings window

A SwiftUI window with these controls:

- Launch at login (`SMAppService`).
- Hidden set: a list of running apps with a checkbox per app. Ellipsis lists apps with a `.regular` or `.accessory` activation policy.
- Always-hidden set: the same list, and a switch to enable the set.
- "Hide apps left of the Ellipsis icon": a switch (F7). Off without the Accessibility permission.
- Auto-rehide: three switches and the timeout value.
- Clock zone: the width, and without the Accessibility permission a "Click the Clock…" button that takes the width from the next click in the menu bar.
- Export and import: the sets and the options above as a property list file. Import ignores unknown keys and refuses a value of the wrong type.
- Version number and a quit button.

Open the window from a right-click menu on the Ellipsis icon. The same menu has "Show always-hidden items", "Settings…", and "Quit".

### F5: App shape

- Menu bar only. `LSUIElement` is true. No Dock icon.
- Minimum macOS: 27.0.
- Swift 6 language mode, strict concurrency.
- Persist settings in `UserDefaults`.

### F6: Optional Accessibility permission

Without the permission, the app pickers (F4) list every running app. With it, Ellipsis asks each app over Accessibility (`AXExtrasMenuBar`) whether it has a menu bar item, and the pickers list only those apps. With it, Ellipsis also reads the clock item's frame from `MenuBarAgent` and fits the clock zone to it. Hiding and showing work the same either way.

- First launch: a dialog explains this and offers "Grant Permission" or "Not Now". "Grant Permission" adds Ellipsis to the Accessibility list and shows the system prompt. "Not Now" is stored and the dialog does not return at launch.
- Settings › General shows "Granted", or a "Grant Permission…" button that opens the same dialog.
- Ellipsis notices a change in System Settings at once, through the `com.apple.accessibility.api` distributed notification.
- Ellipsis never uses Accessibility for anything else.

### F7: The icon as divider

Off by default. When on, the Ellipsis icon divides the menu bar like the Bartender and Ice icons do: Cmd-drag items across it. Needs the Accessibility permission: with it, the windows of `MenuBarAgent` expose every visible item with its frame and owner, and the icon's own window frame gives the split point.

- A visible app left of the icon joins the hidden set. A visible app right of it leaves the set, but only while the set is shown: while it is hidden, a hidden app can still be on its way out.
- An app with an item on each side hides. Hiding is per app.
- Apps that are not visible keep their membership. The always-hidden set is never touched.
- Ellipsis reads the menu bar when the switch turns on, when the set is shown, after a Cmd-drag ends, and after an app launches. Turning the switch on hides whatever already sits left of the icon.
- While the switch is on, the Hidden picker in Settings is read-only.

### F8: The floating bar

A notch splits the menu bar. `MenuBarAgent` never pushes an item off-screen: it fills the status item region from the right, collapses the leftmost items that do not fit, and draws a system `«` button in their place (`docs/phase8.md`). The Ellipsis icon is the leftmost, so it collapses first. On a display with a notch, "show" loses items and the icon. The floating bar shows the hidden apps in a panel below the menu bar instead. The restriction stays active and nothing in the menu bar moves.

No image of an item is available. On macOS 27 the window server has no window per item, so the ScreenCaptureKit method of Ice (capture each item window) does not work. A capture of the menu bar region needs the Screen Recording permission, and it cannot capture an item that is not drawn. So the bar shows the app icon (`NSRunningApplication.icon`) of each hidden app. Hiding is per app, so one icon per app is the same granularity.

- Settings › General has "Show hidden items": "In the menu bar" or "In a bar below the menu bar". Until the user picks one, the default is the bar when a screen has a notch at launch (`NSScreen.safeAreaInsets.top` is more than zero), and the menu bar otherwise.
- In bar mode, a click on the icon shows the panel with one icon per app in the hidden set. An Option click adds the always-hidden set. The icon changes to the chevron as it does today.
- The panel is a non-activating `NSPanel` at the status bar level, on every Space and next to full-screen apps. Its right edge is under the Ellipsis icon. Its top is at the bottom edge of the menu bar. The frontmost app keeps the focus.
- Each icon has a tooltip with the app name. A hover highlights it.
- The rehide conditions of F3 close the panel: timeout, a click outside the panel and the menu bar, and a focus change.
- A click on an icon opens the item of that app (click-through). This needs the Accessibility permission. Ellipsis lets that app through the restriction, reads the menu bar (`MenuBarLayout`) until the item holds still, and presses it over Accessibility (`AXPress`). If the item is collapsed (macOS put it behind `«`), Ellipsis first applies a restriction that hides every other app, so the item fits whenever the region holds two items. The panel closes. Ellipsis applies the normal restriction again when no menu is open.
- Without the permission, nothing can be read, so a click on an icon applies the single-app restriction at once and arms the rehide. The user clicks the item in the menu bar. The tooltip says that the Accessibility permission opens the item with one click.
- An app with an item that changes (a timer, a meter) shows only its app icon in the bar. The README lists this limit.

## Build and distribution

- `Package.swift` with one executable target. No external dependencies.
- `scripts/bundle.sh` assembles `build/Ellipsis.app` from the SwiftPM binary, `Info.plist`, entitlements and the icon.
- `scripts/sign.sh` signs with the Developer ID Application certificate and hardened runtime.
- `scripts/notarize.sh` submits the app with `notarytool`, waits, and staples the ticket.
- `scripts/release.sh` runs the three scripts above and produces a `.zip` or `.dmg`.
- Signing identity and Apple ID come from environment variables. Never commit them.

## Acceptance criteria

1. A fresh install on macOS 27 shows the Ellipsis icon. Ellipsis shows one dialog that offers the optional Accessibility permission. "Not Now" is remembered. macOS shows no prompt of its own.
2. Add an app to the hidden set. Its items disappear. Click the icon. The items return. Click again. The items disappear.
3. Quit and relaunch. The hidden state and the sets are unchanged.
4. Add an app to the always-hidden set. It stays hidden after a normal click. Option+click shows it.
5. Show the set, wait for the timeout. The set hides itself.
6. Show the set, click on the desktop. The set hides itself.
7. Show the set, open the menu of a shown item. The set does not hide while the menu is open.
8. While the hidden set is hidden, move the pointer to the clock and click. Notification Center opens.
9. Quit Ellipsis. Every item returns.
10. `spctl --assess` and `stapler validate` pass on the release build.
11. `swift build` and all scripts run from a terminal with no Xcode project.

## Open risks

- Private API. A macOS 27 point release can rename or remove the `MBAssessmentMode*` classes. Ellipsis checks for them at launch.
- The `/Applications` rule comes from a test on one machine. Other folders that LaunchServices registers, such as `~/Applications`, are not tested.
- If Ellipsis crashes, `MenuBarAgent` drops the restriction when the XPC connection closes. This needs a test.
- Global mouse monitors (`NSEvent.addGlobalMonitorForEvents`) deliver mouse-move and mouse-down events with no Accessibility permission on macOS 27.0. Ellipsis depends on this for the clock hover and for F3 "click outside".
- Open menus of other apps come from `CGWindowListCopyWindowInfo`, deprecated since macOS 14. Its replacement, `SCShareableContent`, needs Screen Recording. If the window list stops reporting pop-up menu windows, the menu-open guard for F3 stops working and a rehide can close a shown item's menu.
- The default clock zone is 300 points, so hidden items show whenever the pointer is near the right end of the menu bar. The measured or clicked zone fixes that, but a clock that grows (a longer date format) can outgrow a clicked zone. The measured zone follows: it is read again when Settings opens.
- The floating bar (F8) is built on displays without a notch. The behavior of `MenuBarAgent` with a notch on macOS 27 comes from one spike on one laptop (`docs/phase8.md`). The single-app restriction for click-through makes the visible items disappear for a moment; with the permission it is used only when the item does not fit on its own.
