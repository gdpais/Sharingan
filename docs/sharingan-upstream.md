---
summary: "Sharingan fork routine: weekly upstream CodexBar merges, the upstream tracking issue, and CI on the fork."
read_when:
  - Merging upstream CodexBar into Sharingan
  - Checking why CI has not run on the fork
  - Deciding what the upstream-monitor workflow is for
---

# Sharingan upstream routine

Sharingan is a fork of [CodexBar](https://github.com/steipete/CodexBar) by Peter Steinberger (MIT). Upstream
ships a release every two to three days and touches 30–50 files per release, so the fork stays cheap to merge
by keeping internal names as CodexBar, preferring new files, and merging upstream **weekly**.

## Weekly merge (Mondays)

```bash
./Scripts/sharingan_upstream_sync.sh --dry-run   # what would conflict, nothing kept
./Scripts/sharingan_upstream_sync.sh             # real run: branch upstream-sync/<date> in a sibling worktree
```

The script:
1. fetches `origin/main` and `steipete/CodexBar` `main`, and stops if there is nothing new;
2. creates `upstream-sync/<YYYY-MM-DD>` from `origin/main` in `../<repo>-upstream-sync-<date>`;
3. merges upstream with a merge commit (never a rebase, so fork history stays intact);
4. resolves the routine conflict in every `Localizable.strings`, where both sides appended keys at the end,
   by keeping Sharingan's block and then upstream's (`Scripts/sharingan_resolve_strings_appends.py`), and
   renames "CodexBar" to "Sharingan" in the **values** of the keys upstream added, never in keys, never
   lowercase `codexbar` (CLI, paths, URL schemes);
5. lists new upstream strings that mention CodexBar and the conflicts left for a person, and never pushes.

Then fix what's listed, run `make check` and the tests, push the branch and open a PR titled
"Merge upstream CodexBar <sha>". Merge it with **Create a merge commit**.

What usually needs a person:
- `README.md`: keep the Sharingan header, the "Based on CodexBar" section and the build-from-source install.
- Hardcoded Swift strings upstream added with the app name (`git grep -n '"[^"]*CodexBar' -- Sources`).
- Packaging identity in `Scripts/package_app.sh` and `.github/release.json` (bundle ID, no update feed).

The first trial run (Nov 4, 2026; upstream 58 commits ahead of 5f93dc3) left only `README.md` after the
strings were resolved automatically.

## Upstream tracking issue

`.github/workflows/upstream-monitor.yml` keeps one open `upstream-sync` issue updated every Monday and
Thursday with upstream's new commits. **Keep it**: it is the reminder for the weekly merge. It also reports
`nguyenphutrong/quotio`, an inspiration source from an earlier fork that Sharingan doesn't follow; dropping
that half of the workflow is a small follow-up (workflow files can't be pushed from Claude's cloud sessions).

## CI on the fork

As of Nov 4, 2026 the repository has **never had a workflow run**, not even for pushes to `main` or for
PRs, although all seven workflows show as active. That is the signature of Actions being disabled for the
fork. To turn it on: repository **Settings → Actions → General → Actions permissions → Allow all actions**,
then push a commit or open a PR (enabling Actions doesn't run anything retroactively).

Once it runs, check the macOS job: `ci.yml` uses `runs-on: xcode-27`. If that job stays queued with no runner,
change it to a GitHub-hosted macOS label available to the account and record the choice here.

Until CI runs, nothing merged into `main` since the fork (Phases 0–1 and later) has been compiled.
