#!/usr/bin/env bash
# Print the one valid "Developer ID Application" identity in the keychain, or
# nothing if there is none. Fail if there are more: a renewed certificate has
# the same name as the old one, so a name cannot pick between them.
# Usage: scripts/developer-id.sh
set -euo pipefail

lines="$(security find-identity -v -p codesigning | grep '"Developer ID Application: ' || true)"
count="$(awk '{print $2}' <<<"$lines" | sort -u | grep -c . || true)"

if [[ "$count" -gt 1 ]]; then
  {
    echo "More than one Developer ID Application identity in the keychain:"
    echo "$lines"
    echo "Remove the old one, or set DEVELOPER_ID to the SHA-1 hash of the one to use."
  } >&2
  exit 1
fi
sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' <<<"$lines"
