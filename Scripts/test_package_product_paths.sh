#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/Scripts/package_product_paths.sh"

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sharingan-package-paths.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT

NATIVE_DIR="$TEMP_DIR/.build/arm64-apple-macosx/release"
SWIFTBUILD_DIR="$TEMP_DIR/.build/out/Products/Release"
STAGE_ROOT="$TEMP_DIR/.build/package-products/release"
mkdir -p "$NATIVE_DIR/Sharingan.dSYM" "$SWIFTBUILD_DIR/Sparkle.framework" "$SWIFTBUILD_DIR/Sharingan.dSYM"
touch "$NATIVE_DIR/Sharingan" "$SWIFTBUILD_DIR/Sharingan"

native=$(sharingan_require_product_file "$NATIVE_DIR" Sharingan arm64)
[[ "$native" == "$NATIVE_DIR/Sharingan" ]]

swiftbuild=$(sharingan_require_product_file "$SWIFTBUILD_DIR" Sharingan arm64)
[[ "$swiftbuild" == "$SWIFTBUILD_DIR/Sharingan" ]]

framework=$(sharingan_require_product_directory "$SWIFTBUILD_DIR" Sparkle.framework packaging)
[[ "$framework" == "$SWIFTBUILD_DIR/Sparkle.framework" ]]

dsym=$(sharingan_require_product_directory "$SWIFTBUILD_DIR" Sharingan.dSYM release)
[[ "$dsym" == "$SWIFTBUILD_DIR/Sharingan.dSYM" ]]

resolved=$(sharingan_resolve_staged_or_reported_file "$STAGE_ROOT" "$SWIFTBUILD_DIR" Sharingan arm64)
[[ "$resolved" == "$SWIFTBUILD_DIR/Sharingan" ]]

resolved_dsym=$(sharingan_resolve_dsym_path "$STAGE_ROOT" "$SWIFTBUILD_DIR" Sharingan arm64)
[[ "$resolved_dsym" == "$SWIFTBUILD_DIR/Sharingan.dSYM" ]]

mkdir -p "$STAGE_ROOT/arm64/Sharingan.dSYM"
touch "$STAGE_ROOT/arm64/Sharingan"
staged=$(sharingan_resolve_staged_or_reported_file "$STAGE_ROOT" "$SWIFTBUILD_DIR" Sharingan arm64)
[[ "$staged" == "$STAGE_ROOT/arm64/Sharingan" ]]
staged_dsym=$(sharingan_resolve_dsym_path "$STAGE_ROOT" "$SWIFTBUILD_DIR" Sharingan arm64)
[[ "$staged_dsym" == "$STAGE_ROOT/arm64/Sharingan.dSYM" ]]

rm -rf "$STAGE_ROOT"
rm "$SWIFTBUILD_DIR/Sharingan"
if sharingan_resolve_staged_or_reported_file "$STAGE_ROOT" "$SWIFTBUILD_DIR" Sharingan arm64 \
  2>"$TEMP_DIR/missing-file.log"; then
  echo "ERROR: Missing reported product unexpectedly fell back to legacy output." >&2
  exit 1
fi
grep -Fq "$SWIFTBUILD_DIR/Sharingan" "$TEMP_DIR/missing-file.log"

rm -rf "$SWIFTBUILD_DIR/Sparkle.framework"
if sharingan_require_product_directory "$SWIFTBUILD_DIR" Sparkle.framework packaging \
  2>"$TEMP_DIR/missing-directory.log"; then
  echo "ERROR: Missing reported framework was accepted." >&2
  exit 1
fi
grep -Fq "$SWIFTBUILD_DIR/Sparkle.framework" "$TEMP_DIR/missing-directory.log"

rm -rf "$SWIFTBUILD_DIR/Sharingan.dSYM"
if sharingan_resolve_dsym_path "$STAGE_ROOT" "$SWIFTBUILD_DIR" Sharingan arm64 \
  2>"$TEMP_DIR/missing-dsym.log"; then
  echo "ERROR: Missing reported dSYM unexpectedly fell back to legacy output." >&2
  exit 1
fi
grep -Fq "$SWIFTBUILD_DIR/Sharingan.dSYM" "$TEMP_DIR/missing-dsym.log"

swift() {
  [[ "$*" == "build --show-bin-path -c release --arch arm64" ]]
  printf '%s\n' "$SWIFTBUILD_DIR"
}
reported=$(sharingan_swiftpm_bin_path release arm64)
[[ "$reported" == "$SWIFTBUILD_DIR" ]]

swift() {
  return 23
}
if sharingan_swiftpm_bin_path release arm64 2>"$TEMP_DIR/query.log"; then
  echo "ERROR: SwiftPM bin-path query failure was ignored." >&2
  exit 1
fi
grep -Fq "SwiftPM failed to report" "$TEMP_DIR/query.log"

swift() {
  return 0
}
if sharingan_swiftpm_bin_path release arm64 2>"$TEMP_DIR/empty.log"; then
  echo "ERROR: Empty SwiftPM bin path was accepted." >&2
  exit 1
fi
grep -Fq "SwiftPM reported an empty" "$TEMP_DIR/empty.log"

# Exercise the real staging boundary with the SDK metadata emitted by SwiftBuild.
python3 - "$ROOT/Scripts/package_app.sh" "$TEMP_DIR/staging.sh" <<'PY'
import sys
from pathlib import Path

script = Path(sys.argv[1]).read_text()
start = script.index('stage_build_products() {')
end = script.index('\n}\n', start) + 3
Path(sys.argv[2]).write_text(script[start:end])
PY
source "$TEMP_DIR/staging.sh"
swiftpm_bin_path() { printf -v "$2" '%s' "$SWIFTBUILD_DIR"; }
binary_has_arch() { return 0; }
otool() {
  printf '      cmd LC_BUILD_VERSION\n    minos %s\n      sdk %s\n' "$MOCK_MINOS" "$MOCK_SDK"
}
touch "$SWIFTBUILD_DIR/Sharingan" "$SWIFTBUILD_DIR/SharinganCLI" "$SWIFTBUILD_DIR/SharinganClaudeWatchdog"
PRODUCT_STAGE_ROOT="$STAGE_ROOT"
SDK_VERSION=27.2
MOCK_MINOS=14.0
MOCK_SDK=14.0
if stage_build_products arm64 2>"$TEMP_DIR/metadata.log"; then
  echo "ERROR: Staging accepted the deployment target as the linked SDK." >&2
  exit 1
fi
MOCK_SDK="$SDK_VERSION"
MOCK_MINOS=27.0
if stage_build_products arm64 2>"$TEMP_DIR/metadata.log"; then
  echo "ERROR: Staging accepted a raised minimum macOS version." >&2
  exit 1
fi
MOCK_MINOS=14.0
stage_build_products arm64
for name in Sharingan SharinganCLI SharinganClaudeWatchdog; do
  [[ -f "$STAGE_ROOT/arm64/$name" ]]
done

echo "Package product path and SDK metadata tests passed."
