#!/bin/sh
set -eu
package_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
exec python3 "${package_root}/Scripts/install-app.py" "$@"
