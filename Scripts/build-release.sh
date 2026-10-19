#!/bin/sh
set -eu
package_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
python3 "${package_root}/Scripts/build-app.py"
archive="${package_root}/artifacts/WCH-Touch-Driver.zip"
ditto -c -k --keepParent "${package_root}/artifacts/WCH Touch Driver.app" "$archive"
if [ -n "${NOTARIZATION_PROFILE:-}" ]; then
  xcrun notarytool submit "$archive" --keychain-profile "$NOTARIZATION_PROFILE" --wait
  xcrun stapler staple "${package_root}/artifacts/WCH Touch Driver.app"
  ditto -c -k --keepParent "${package_root}/artifacts/WCH Touch Driver.app" "$archive"
fi
echo "Built ${archive}"
