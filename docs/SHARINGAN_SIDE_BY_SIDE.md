---
summary: "Where Sharingan keeps its config, Keychain items, caches, and CLI so it can run beside CodexBar."
read_when:
  - Running Sharingan and CodexBar on the same Mac
  - Adding code that writes files, defaults, Keychain items, or logs
---

# Running Sharingan beside CodexBar

Sharingan shares no runtime state with CodexBar, so both apps can run at the same time. Every name below comes from
`Sources/CodexBarCore/AppIdentity.swift` (plus `AppDefaultsDomain` and `Scripts/package_app.sh`); new code must use
those constants instead of hard-coding a path.

| What | Sharingan | CodexBar |
| --- | --- | --- |
| App bundle / executable | `Sharingan.app/Contents/MacOS/Sharingan` | `CodexBar.app/Contents/MacOS/CodexBar` |
| Bundle ID / defaults domain | `com.gdpais.sharingan` (`.debug` for debug builds) | `com.steipete.codexbar` |
| Config file | `~/.config/sharingan/config.json` (legacy `~/.sharingan/config.json`) | `~/.config/codexbar/config.json` (legacy `~/.codexbar/config.json`) |
| Config override env var | `SHARINGAN_CONFIG` | `CODEXBAR_CONFIG` |
| User provider plugins | `~/.config/sharingan/providers` | `~/.config/codexbar/providers` |
| Keychain services | `com.gdpais.sharingan`, `com.gdpais.sharingan.cache` | `com.steipete.CodexBar`, `com.steipete.codexbar.cache` |
| App group (app + widget) | `<team>.com.gdpais.sharingan` | `<team>.com.steipete.codexbar` |
| Application Support | `~/Library/Application Support/Sharingan`, `…/com.gdpais.sharingan` | `…/CodexBar`, `…/com.steipete.codexbar` |
| Caches | `~/Library/Caches/Sharingan` | `~/Library/Caches/CodexBar` |
| Logs | `~/Library/Logs/Sharingan/Sharingan.log`, os_log subsystem `com.gdpais.sharingan` | `~/Library/Logs/CodexBar/CodexBar.log` |
| Other home-dir state | `~/.sharingan/` (Antigravity, MiMo, Claude cache-clear marker) | `~/.codexbar/` |
| CLI symlink | `sharingan` in `/usr/local/bin` or `/opt/homebrew/bin` | `codexbar` |

## Moving your CodexBar setup over

Sharingan starts with no providers configured. To reuse CodexBar's provider toggles and API keys, copy its config once:

```bash
mkdir -p ~/.config/sharingan
cp ~/.config/codexbar/config.json ~/.config/sharingan/config.json  # or ~/.codexbar/config.json
chmod 600 ~/.config/sharingan/config.json
```

Secrets CodexBar stored in the Keychain (not in the config file) are not copied; re-enter them in Sharingan's
Settings. On first launch Sharingan imports CodexBar's display preferences (menu bar and layout choices) read-only;
CodexBar's defaults are never modified.

## Development

- `./Scripts/compile_and_run.sh` only kills processes running from `Sharingan.app` or this checkout's `.build`, so a
  running CodexBar stays up. To restart by hand use `pkill -x Sharingan || true; open -n ./Sharingan.app`. Never use
  `pkill -x CodexBar`.
- `--clear-adhoc-keychain` only deletes Sharingan's Keychain services.
- Source names stay upstream's (`CodexBar`, `CodexBarCore`, `CodexBarCLI`, `CODEXBAR_*` env vars other than the config
  path) to keep upstream merges small.
