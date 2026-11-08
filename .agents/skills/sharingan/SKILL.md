---
name: sharingan
description: "Sharingan read. Provider usage, limits, credits, config health. JSON. No writes."
---

# Sharingan

Read Sharingan. Never mutate config/auth.

## Run

```bash
skill="${CODEX_HOME:-$HOME/.codex}/skills/sharingan"
"$skill/scripts/sharingan" doctor
"$skill/scripts/sharingan" providers
"$skill/scripts/sharingan" usage
"$skill/scripts/sharingan" usage --provider codex
"$skill/scripts/sharingan" usage --all
```

All stdout: JSON. Upstream Sharingan shape kept. Less drift, fewer tokens.

## Rules

- Start `doctor` when install/config unknown.
- `usage` reads enabled providers. Prefer this.
- `usage --provider ID` reads one provider.
- `usage --all` expensive; use only when needed.
- Identities hidden by default. `--include-identities` only when user explicitly needs them.
- Secrets always hidden.
- Helper read-only: fixed allowlist only. No config writes, auth repair, enable/disable, key storage.
- Timeout means upstream stuck. Narrow provider or raise `SHARINGAN_TIMEOUT` (default 120 seconds).

## Binary

Auto-find: `SHARINGAN_BIN`, PATH, app bundle, Homebrew cask. If missing: open Sharingan, Preferences > Advanced > Install CLI; or set `SHARINGAN_BIN`.

Each stdout/stderr stream capped at 1 MiB while fully drained. Timeout kills process group.
