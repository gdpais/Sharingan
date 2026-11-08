---
name: release-sharingan
description: "Sharingan release: versioning, notarization, GitHub Releases, post-release bump."
---

# Sharingan Release

Use for releasing Sharingan to GitHub Releases, its only distribution channel (no Homebrew, no website). CI publication and first-release prerequisites are in `docs/RELEASING.md`.

## Start

1. Work from the app repo unless asked otherwise.
2. Check repo state, current version, latest tag/release, and release docs/scripts.
3. Confirm `CHANGELOG.md` is complete, user-facing, deduped, and dated for the release.
4. Prefer the repo release script; patch small script/test blockers instead of bypassing the release path.
5. Never print key material. Keep 1Password references and local key paths as references only.
6. Load `$release-private` if it exists before resolving Peter-owned credential locators.

## Key Material

Use `$one-password` for secret handling. `op` only in tmux/persistent shell; no broad `env`, `set`, `export -p`, or secret scans.

Known App Store Connect shape:

- fields: `private_key_p8`, `key_id`, `issuer_id`
- keep all three fields from the same 1Password item; do not mix with stale values from `~/.profile`
- resolve Peter-owned item refs from `$release-private`

Known Sparkle key:

- resolve the private key file from `$release-private`
- pass as `SPARKLE_PRIVATE_KEY_FILE`

Safe env file pattern:

```text
APP_STORE_CONNECT_API_KEY_P8=<1Password ref from release-private>
APP_STORE_CONNECT_KEY_ID=<1Password ref from release-private>
APP_STORE_CONNECT_ISSUER_ID=<1Password ref from release-private>
SPARKLE_PRIVATE_KEY_FILE=<path from release-private>
```

Run with `op run --account my.1password.com --env-file <file> -- <script>`, then delete the temp env file.

## Sharingan

Paths:

- repo: `~/Projects/sharingan`
- release script: `Scripts/release.sh`
- signing/notarization: `Scripts/sign-and-notarize.sh`
- appcast: `Scripts/make_appcast.sh`, `appcast.xml`
- release assets: `Sharingan-macos-universal-<version>.zip`, `Sharingan-macos-universal-<version>.dSYM.zip`
- packaged app: `Sharingan.app`
- version file: `version.env`
- changelog: `CHANGELOG.md`
- CLI release workflow: `.github/workflows/release-cli.yml`

Normal release:

```bash
tmux new-session -d -s sharingan-release 'op run --account my.1password.com --env-file /tmp/sharingan-release-op.env -- Scripts/release.sh'
tmux attach -t sharingan-release
```

If notarization fails with `401 Unauthenticated`, rerun using all three App Store Connect fields from the 1Password item above. Mismatched `key_id` / `issuer_id` from `~/.profile` can cause this.

If widget metadata generation times out, `SHARINGAN_WIDGET_METADATA_TIMEOUT_SECONDS=600` is a known-good floor.

Sharingan CLI tarballs are not produced by `Scripts/release.sh` itself. The GitHub release event triggers `.github/workflows/release-cli.yml`, which builds and uploads:

- `SharinganCLI-v<version>-macos-arm64.tar.gz`
- `SharinganCLI-v<version>-macos-x86_64.tar.gz`
- `SharinganCLI-v<version>-linux-aarch64.tar.gz`
- `SharinganCLI-v<version>-linux-x86_64.tar.gz`
- matching `.sha256` files

## Verify

Release is not done until the published chain checks out:

```bash
gh release view v<VERSION> --json tagName,name,isDraft,isPrerelease,url,assets,body
Scripts/check-release-assets.sh v<VERSION>
python3 - <<'PY'
import xml.etree.ElementTree as ET
ns={'sparkle':'http://www.andymatuschak.org/xml-namespaces/sparkle'}
root=ET.parse('appcast.xml').getroot()
item=root.find('channel').find('item')
enc=item.find('enclosure')
print(item.findtext('title'))
print(item.findtext('sparkle:version', namespaces=ns))
print(item.findtext('sparkle:shortVersionString', namespaces=ns))
print(enc.attrib.get('url'))
print(enc.attrib.get('length'))
print(bool(enc.attrib.get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature')))
PY
codesign --verify --deep --strict --verbose=2 Sharingan.app
spctl --assess --type execute --verbose Sharingan.app
```

## Closeout

1. Create/push tag and GitHub release through the release script.
2. Verify appcast points to the new GitHub release asset with signature and length.
3. Bump the app repo to next patch `Unreleased`:
   - `version.env`: next `MARKETING_VERSION`, next `BUILD_NUMBER`
   - `CHANGELOG.md`: top `## <next> — Unreleased`
4. Commit, push, then pull `--ff-only`.
5. Restart the local app from the packaged bundle and verify the running bundle version.
6. Check no release/notary/op temp sessions or temp env files remain.

Sharingan restart:

```bash
pkill -x Sharingan || pkill -f Sharingan.app || true
cd "$(git rev-parse --show-toplevel)"
open -n Sharingan.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sharingan.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sharingan.app/Contents/Info.plist
```
