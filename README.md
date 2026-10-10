# Ellipsis

Ellipsis hides selected menu bar items on macOS 27. Click its icon to show them. Click again, or wait, to hide them again.

## Requirements

- macOS 27.0 or later.
- Ellipsis must run from `/Applications`. `MenuBarAgent` matches the allow-list against apps in that folder only. A copy in any other folder, or a copy that macOS translocates, hides nothing and offers to move itself to `/Applications`.
- No permission is necessary. Ellipsis offers the Accessibility permission once, as an option. See Limits.

## Install a release

1. Download `Ellipsis-X.Y.Z.zip` from [GitHub Releases](../../releases).
2. Open the zip. Drag `Ellipsis.app` to `/Applications` in the Finder. A move with `mv` keeps the quarantine, and macOS then runs the app from a temporary folder (App Translocation).
3. Open Ellipsis. The `…` icon appears in the menu bar.
4. Right-click the icon. Select "Settings…". Put apps in the hidden set. Or, with the Accessibility permission, turn on "Hide apps left of the Ellipsis icon" and Cmd-drag items to the left of the icon.

On a MacBook with a notch, a shown set may not fit in the menu bar. macOS then collapses the items that do not fit behind a `«` button, the Ellipsis icon first. So on a notch display, Ellipsis shows the hidden apps in a bar below the menu bar instead, one app icon per app, and the menu bar stays as it is. A click on an app in the bar opens its menu bar item. Settings › General › "Show hidden items" switches between the bar and the menu bar on any display.

Ellipsis checks GitHub Releases for updates with [Sparkle](https://sparkle-project.org). At the second launch, it asks whether it can check on its own. "Check for Updates…" in the icon menu checks now.

## Limits

- Private API. Ellipsis loads `MenuBarClientCore.framework` and uses its `MBAssessmentMode` classes. A macOS update can rename or remove them. Ellipsis checks for the classes at launch and shows an alert if they are missing.
- Focus and the camera/microphone indicator are hidden while any set is hidden. No setting brings them back. This is a limit of the API.
- The hidden sets hold whole apps, not single items. An app with two menu bar items hides both.
- The bar below the menu bar shows app icons, not the items. An item that changes (a timer, a meter) shows only its app icon there. Opening an item from the bar with one click needs the Accessibility permission; without it, a click puts that app's item alone in the menu bar for you to click.
- The app pickers in Settings list every running app, not only apps with a menu bar item. With the Accessibility permission, they list only apps with a menu bar item, the icon can work as a divider (Cmd-drag items to its left to hide them), and the clock zone fits the clock. The permission is optional. Ellipsis asks once at first launch, and again only from Settings.

## Alternatives

- [Ice](https://github.com/jordanbaird/Ice), doesn't work in macOS 27 at the time of writing.
- [Thaw](https://github.com/thaw-app/Thaw), doesn't work in macOS 27 at the time of writing.
- [Bartender 7](https://www.macbartender.com/bartender7)

## Development

See [docs/development.md](docs/development.md) for how to build, test and release.

## License

Ellipsis is under the Apache License 2.0. See [LICENSE](LICENSE).
