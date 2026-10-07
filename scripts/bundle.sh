#!/usr/bin/env bash
# Assemble the app bundle from the SwiftPM binary and sign it.
# A debug build is build/EllipsisDev.app with the identifier
# au.ronny.EllipsisDev, so it sits next to the release app in /Applications
# and in the Accessibility list, with its own settings. A release build is
# build/Ellipsis.app with au.ronny.Ellipsis; sign.sh signs it for release.
# The signature here uses the Developer ID Application identity in the
# keychain (see developer-id.sh), else the first Apple Development one, else
# ad hoc. An ad hoc
# signature changes with every build, and macOS ties the Accessibility grant
# to the signature, so an ad hoc debug build loses the permission at every
# rebuild. Any certificate keeps it.
# Usage: scripts/bundle.sh [debug|release]   (default: debug)
# VERSION and BUILD override CFBundleShortVersionString and CFBundleVersion.
# DEVELOPER_ID names the identity.
set -euo pipefail

config="${1:-debug}"
root="$(cd "$(dirname "$0")/.." && pwd)"
bin="$(swift build -c "$config" --package-path "$root" --show-bin-path)/Ellipsis"

name="Ellipsis"
[[ "$config" == "release" ]] || name="EllipsisDev"
identifier="au.ronny.$name"
app="$root/build/$name.app"

swift build -c "$config" --package-path "$root" >&2

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$root/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
mkdir -p "$app/Contents/Frameworks"
ditto "$root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" \
  "$app/Contents/Frameworks/Sparkle.framework"
echo -n "APPL????" > "$app/Contents/PkgInfo"

plist="$app/Contents/Info.plist"
plutil -replace CFBundleExecutable -string "$name" "$plist"
plutil -replace CFBundleName -string "$name" "$plist"
plutil -replace CFBundleIdentifier -string "$identifier" "$plist"
[[ -z "${VERSION:-}" ]] || plutil -replace CFBundleShortVersionString -string "$VERSION" "$plist"
[[ -z "${BUILD:-}" ]] || plutil -replace CFBundleVersion -string "$BUILD" "$plist"
# A debug build still offers "Check for Updates…" but never checks on its own,
# so it does not ask about automatic checks or replace itself with a release.
[[ "$config" == "release" ]] || plutil -replace SUEnableAutomaticChecks -bool false "$plist"

identity="${DEVELOPER_ID:-}"
[[ -n "$identity" ]] || identity="$("$root/scripts/developer-id.sh")"
[[ -n "$identity" ]] || identity="$(security find-identity -v -p codesigning |
  sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
codesign --force --sign "${identity:--}" --identifier "$identifier" "$app"
echo "$app"
