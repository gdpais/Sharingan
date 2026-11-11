---
summary: "Sharingan CI release pipeline, dry runs, and signing. GitHub Releases is the only distribution channel."
read_when:
  - Preparing or verifying a Sharingan release
  - Updating release infrastructure
---

# Release process (Sharingan)

Sharingan is distributed only through [GitHub Releases](https://github.com/gdpais/Sharingan/releases): no Homebrew
cask or formula, no package-manager packages, and no website.

## Before the first release

The pipeline came from CodexBar and still expects credentials Sharingan does not have yet:

1. **Developer ID signing and notarization.** Add your own `MACOS_SIGNING_P12`, `MACOS_SIGNING_P12_PASSWORD`,
   `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_PRIVATE_KEY_P8` secrets (an Apple Developer Program membership is
   required), and set `APP_IDENTITY` in `Scripts/sign-and-notarize.sh` to your Developer ID Application identity.
2. **Sparkle appcast.** The workflow still signs and publishes `appcast.xml` with `SPARKLE_PRIVATE_KEY`, and the
   `sparkle_public_key` in `.github/release.json` is CodexBar's. Either generate Sharingan's own EdDSA key pair
   (public key in `.github/release.json`, private key as the secret) or remove the appcast steps from the workflow.
   The app itself ships without a feed (`TODO(sharingan)` in `Scripts/package_app.sh`).
3. **Release signers.** Replace `.github/release-allowed-signers` with your own SSH signing key.

[Release](https://github.com/gdpais/Sharingan/blob/main/.github/workflows/release.yml) owns publication. Push an existing SSH-signed, annotated `vX.Y.Z` (or `vX.Y.Z-beta.N`) tag to run the pipeline, or dispatch it from protected `main` with that existing tag and `dry_run=false`. It never creates, moves, or overwrites a version tag. Local publishing through `Scripts/release.sh` and `Scripts/make_appcast.sh` has been retired.

## Rehearse without publishing

```sh
gh workflow run release.yml --ref main -f dry_run=true
```

A dispatch defaults to a dry run of the exact protected main head. It requires green push CI for that commit, builds every shipping artifact, signs and notarizes the app, verifies metadata, architecture, deployment targets and matching dSYM UUIDs, smokes the app, and signs/verifies a candidate Sparkle feed. It retains the complete checksummed payload as an Actions artifact. It creates no tag, GitHub Release, or live appcast update. An Unreleased changelog section is allowed for this rehearsal.

## Prepare a release

Only release when explicitly requested. Set `version.env` and all version metadata, then finalize a nonempty `## X.Y.Z — YYYY-MM-DD` changelog section at the top. The date must not be in the future. Increment the build number beyond every published appcast entry. Merge and wait for green **push** CI on the exact commit before creating the signed annotated tag using an allowed signer in `.github/release-allowed-signers`.

The pipeline verifies that the tag resolves to a commit on protected main, checks the signature and version, and refuses any existing GitHub Release, including drafts. App packaging stays in `Scripts/sign-and-notarize.sh`; the CI job supplies an ephemeral personal Developer ID keychain and App Store Connect credentials. The app and dSYM archive names stay compatible with existing downloads.

All platform builds finish before publication. The publisher verifies uploaded draft bytes against the retained payload, publishes the GitHub Release with changelog notes and checksums, and updates `main/appcast.xml`.

Required repository secrets are `MACOS_SIGNING_P12`, `MACOS_SIGNING_P12_PASSWORD`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_P8`, and `SPARKLE_PRIVATE_KEY` (see [Before the first release](#before-the-first-release)). The Sparkle private key must match the public key in `.github/release.json`; the signing certificate must be the owner's Developer ID Application identity. No npm package is published by this repository.

Prereleases (`alpha.N`, `beta.N`, or `rc.N`) are marked as GitHub prereleases and use the opt-in Sparkle `beta` channel. They do not replace GitHub’s latest stable release.

## Verify and recover

The release is complete only after the release assets and live appcast agree. The pipeline preserves a failed draft as a version reservation and never clobbers assets. If the feed handoff fails after publication, inspect the retained payload and repair that handoff from the verified bytes; do not rerun packaging or recreate the tag. After a successful release, open the next Unreleased changelog section.

Local read-only helpers remain: `Scripts/check-release-assets.sh`, `Scripts/verify_appcast.sh`, and `Scripts/generate-release-notes.sh` (where present). They need the shared `agent-scripts` helper but no signing credentials: `Scripts/verify_appcast.sh <version>` downloads that appcast entry's enclosure, checks its length and EdDSA signature against `SUPublicEDKey`, then verifies the app's code signature, Gatekeeper assessment, and stapled notarization. Local packaging and development scripts remain available, but publication belongs to CI. When installing a ZIP manually, use `ditto -x -k` or Finder to preserve the signed bundle and avoid AppleDouble files.

The app and dSYM are universal arm64/x86_64. The release also contains both architectures of the macOS CLI, Linux glibc CLI, Linux musl CLI, and Linux desktop.

All macOS release jobs use Apple Silicon `xcode-27` runners and Xcode 27 while
retaining the macOS 14 deployment target. The x86_64 CLI is cross-built and
executed under Rosetta. Signed app verification launches both architectures.

## iCloud sync (CloudKit)
Upstream-team identity-signed release builds embed `Scripts/profiles/Sharingan-DeveloperID.provisionprofile` at `Contents/embedded.provisionprofile` and claim the iCloud entitlements (`Scripts/package_app.sh` does both automatically; it fails hard if the profile file is missing). Packaging derives the team from the selected `APP_IDENTITY`; other teams omit upstream CloudKit resources. `sign-and-notarize.sh` honors that same identity, with required timestamping and hardened runtime. The profile expires 2044-07-29; Gatekeeper re-validates it at every launch.

Push delivery setup is pending owner approval (#4132): enable **Push Notifications** for the macOS App ID `com.gdpais.sharingan`, regenerate its Developer ID provisioning profile, and replace the profile above with one authorizing `com.apple.developer.aps-environment = production`. Then add that exact entitlement and value to the upstream release-only entitlement block in `Scripts/package_app.sh` and extend `Scripts/test_package_signing.sh`. The macOS key is `com.apple.developer.aps-environment`, not the iOS `aps-environment` key. Verify both the embedded profile and final signed app authorize it before publishing. The runtime registers only when CloudKit and a valid push entitlement are present; CKSyncEngine creates or reuses its own `CKDatabaseSubscription`, so no separate subscription or CloudKit schema change is needed. Confirm changes arrive between two signed-in Macs before closing #4132. Registration alone does not repair releases signed without this capability.

Schema changes: any new record type or field in `Sources/Sharingan*/Sync/` must be reflected in `Scripts/cloudkit/schema.ckdb` and deployed **before** shipping the build:
```
CLOUDKIT_MANAGEMENT_TOKEN=… Scripts/cloudkit/deploy_schema.sh development   # validate
CLOUDKIT_MANAGEMENT_TOKEN=… Scripts/cloudkit/deploy_schema.sh production
```
Tokens come from the CloudKit Console (icloud.developer.apple.com → account → Tokens). Developer ID builds can only reach the Production environment — an undeployed schema means every sync save fails with "unknown record type".
