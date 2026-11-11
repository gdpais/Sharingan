---
summary: "Sparkle integration details for Sharingan: updater config, keys, and release flow."
read_when:
  - Touching Sparkle settings, feed URL, or keys
  - Generating or troubleshooting the Sparkle appcast
  - Validating update toggles or updater UI
---

# Sparkle integration

> **Sharingan status:** Sparkle is built in but **disabled**. Sharingan ships with an empty `SUFeedURL` and no
> `SUPublicEDKey`, so the app never checks for updates and hides "Check for Updates". Users update by downloading the
> newer build from [GitHub Releases](https://github.com/gdpais/Sharingan/releases). The rest of this page describes how
> the updater works once Sharingan has its own appcast and EdDSA key (`TODO(sharingan)` in `Scripts/package_app.sh`).

- Framework: Sparkle 2.9.6 via SwiftPM.
- Updater: `SPUStandardUpdaterController` owned by `AppDelegate` in `SharinganApp.swift`.
- Feed: `SUFeedURL` in Info.plist (empty in Sharingan builds; would point to the GitHub Releases appcast, `appcast.xml`).
- Key: `SUPublicEDKey` (empty in Sharingan builds). The `AGCY…` key in `.github/release.json` is CodexBar's; generate Sharingan's own Ed25519 key pair before enabling updates and keep the private key safe.
- UI: About has separate toggles for automatic checks and automatic download-and-install (both on by default, with the install toggle disabled while checks are off); menu shows “Check for Updates…” when no update is staged, or “Update ready, restart now?” once an update is downloaded. These actions and About → Check for Updates open Sparkle's update UI, including its install confirmation for a staged update.
- LSUIElement: works; updater window will show when checking. App is non-sandboxed.
- Channels: stable vs beta are served from the same appcast. Prerelease items contain a `<sparkle:channel>beta</sparkle:channel>` element; About → Update Channel controls `allowedChannels`.

## Release flow

The [CI release workflow](https://github.com/gdpais/Sharingan/blob/main/.github/workflows/release.yml) builds and notarizes the app, signs and verifies its appcast entry, publishes the verified assets, and updates the existing feed on main. See [the release process](RELEASING.md) for signed tags and no-publish dry runs. Prerelease versions such as `X.Y.Z-beta.N` stay on the opt-in beta channel.

## Notes
- Release notes are embedded as Markdown in `<description sparkle:format="markdown">`, with linked GitHub issue and contributor references. Sparkle 2.9+ renders headings, lists, and wrapping text on macOS 12+; Sharingan supports macOS 14+. Older Sharingan builds carrying Sparkle 2.8.1 display these notes as readable plain text and can still install the update. Keep the format attribute: without it, Sparkle interprets the description as HTML.
- If you change the feed host or key, update Info.plist (`SUFeedURL`, `SUPublicEDKey`) and bump the app.
- Auto-check is persisted in Sharingan's `autoUpdateEnabled` default and applied to Sparkle at launch. Automatic install is persisted only by Sparkle (`SUAutomaticallyUpdate`, Info.plist default `true`), so the Settings toggle and Sparkle's update-alert checkbox stay in sync; Sharingan never writes it at launch. New installations retain the previous default-on behavior. Existing installations retain their saved install choice, including an explicit opt-out; no migration resets opt-ins or opt-outs. Settings observes the stored install choice directly because Sparkle’s effective download flag is false while checks are disabled. Manual “Check for Updates…” remains in About.
- Sparkle retains installation control after a background download. The install-on-quit delegate records update readiness and returns `false`; returning `true` stalls Sparkle's update session and causes manual checks to do nothing. Dismissing a downloaded or staged installation keeps the update-ready menu action available.
- Sparkle is also disabled in unsigned builds. The Homebrew updater code inherited from CodexBar only activates for CodexBar's own bundle ID, so it never runs in Sharingan; Sharingan is not distributed through Homebrew.
