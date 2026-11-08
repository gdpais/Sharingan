#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PACKAGE_SCRIPT="$ROOT/Scripts/package_app.sh"
PLIST_SCRIPT=$(mktemp "${TMPDIR:-/tmp}/sharingan-package-info-plist-script.XXXXXX")
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sharingan-package-info-plist.XXXXXX")
trap 'rm -f "$PLIST_SCRIPT"; rm -rf "$TEMP_DIR"' EXIT

python3 - "$PACKAGE_SCRIPT" "$PLIST_SCRIPT" <<'PY'
import sys
from pathlib import Path

script = Path(sys.argv[1]).read_text()
# Sharingan: use the real release identity/update settings so the feed stays disabled in every build.
assert 'steipete/CodexBar/main/appcast.xml' not in script
identity_start = script.index('BUNDLE_ID="com.gdpais.sharingan"')
identity_end = script.index('if [[ "$LOWER_CONF" == "debug" ]]; then', identity_start)
start = script.index('cat > "$APP/Contents/Info.plist" <<PLIST')
end = script.index('\nPLIST\n', start) + len('\nPLIST\n')
exe_start = script.index('APP_EXECUTABLE="')
exe_line = script[exe_start:script.index('\n', exe_start) + 1]
Path(sys.argv[2]).write_text(exe_line + script[identity_start:identity_end] + script[start:end])
PY

APP="$TEMP_DIR/Sharingan.app"
mkdir -p "$APP/Contents"
MARKETING_VERSION=0.0.0
BUILD_NUMBER=0
BUILD_TIMESTAMP=2026-01-01T00:00:00Z
GIT_COMMIT=test
APP_TEAM_ID=TESTTEAM
source "$PLIST_SCRIPT"

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$APP/Contents/Info.plist"
fi
python3 - "$APP/Contents/Info.plist" <<'PY'
import plistlib
import sys
from pathlib import Path

plist = plistlib.loads(Path(sys.argv[1]).read_bytes())
assert plist.get("CFBundleIdentifier") == "com.gdpais.sharingan"
assert plist.get("CFBundleName") == "Sharingan"
assert plist.get("CFBundleDisplayName") == "Sharingan"
assert plist.get("CFBundleExecutable") == "Sharingan"
assert "Peter Steinberger" in plist.get("NSHumanReadableCopyright", "")
# No update feed until Sharingan has its own appcast and Sparkle key (see TODO(sharingan) in package_app.sh).
assert plist.get("SUFeedURL") == ""
assert "SUPublicEDKey" not in plist
assert plist.get("SUEnableAutomaticChecks") is False
assert plist.get("SUAutomaticallyUpdate") is False
declarations = plist.get("UTExportedTypeDeclarations")
assert declarations == [{
    "UTTypeIdentifier": "com.gdpais.sharingan.menu-layout-item",
    "UTTypeDescription": "Sharingan menu bar layout token",
    "UTTypeConformsTo": ["public.data"],
    "UTTypeTagSpecification": {},
}]
PY

echo "Package Info.plist tests passed."
