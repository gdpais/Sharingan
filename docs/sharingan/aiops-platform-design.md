---
summary: "System design for growing Sharingan from token-usage monitoring into a local AIOps console for AI coding agents: spend, resources, live session inspection, logs, and traces."
read_when:
  - Planning Sharingan work after Phase 1 (charts)
  - Adding resource sampling, session inspection, log search, insights, or OTLP ingest/export
  - Deciding where new fork-owned telemetry code and storage should live
---

# Sharingan AIOps platform: system design

Status: **Draft, 2026-11-05.** It continues the fork's phase numbering. Phase 0 was the rebrand
(gdpais/Sharingan#1) and Phase 1 the chart fixes (gdpais/Sharingan#2). This document plans Phases 2–8.

## 1. Summary

Sharingan today answers one question: *what have my AI subscriptions and APIs cost me, and how close am I to
the limits?* This design widens it to a local operations console for AI coding agents:

> **Sharingan shows what your agents cost, what they consume, what they are doing right now, and what they
> left behind. It runs locally and is private by default.**

The work has five pillars plus one cross-cutting layer:

| Pillar | Question it answers | State today |
|---|---|---|
| **Spend** | Tokens, quotas, cost, pace | Mature (upstream CodexBar) |
| **Resources** | CPU, memory, disk I/O, energy and ports per agent session; leftover servers and worktrees; clean-up | Process discovery only |
| **Sessions** | Live state, step timeline, plan progress, and an interpretation of mid-session steps | Discovery, per-turn cost, and Codex-only tool activity |
| **Logs** | Searchable, normalized agent events and tool diagnostic logs | None |
| **Traces** | An OpenTelemetry-shaped model, with OTLP in and out for integrations | None |
| *Insights* (cross-cutting) | Deterministic detectors for loops, stalls, cost spikes, runaway processes and leftovers | Quota pace warnings only |

The design adds **one host-agnostic telemetry engine**: a new `CodexBarTelemetry` SwiftPM target with its own
SQLite store. It ingests from three kinds of source:

1. Agent transcripts already on disk. These need zero setup and are the primary source.
2. Process sampling of each agent's process tree.
3. Optional push sources: Claude Code hooks, and OTLP from agents that export OpenTelemetry.

The same engine runs inside the menu bar app on macOS, or inside `codexbar serve --collect` on Linux and
headless machines. A single-writer lease lets the two hosts swap without coordination. Every surface reads from
the same store: menu, Console window, CLI, web UI and HTTP API.

Reference product for the Resources pillar: **Mizu** (usemizu.com). Per its public homepage it puts dev
servers, Claude Code and Codex agents, usage limits and clean-up in one menu bar panel. It finds what a finished
session left behind (running servers, taken ports, worktrees, caches) and removes only items that session
created. Every item is listed before removal, and worktrees with uncommitted changes are never deleted. This
design adopts those safety rules unchanged.

## 2. Goals and non-goals

### Goals

- **G1. Resource visibility per session.** For each agent session, show CPU, memory footprint, disk I/O and
  energy, aggregated over its whole process tree. That tree includes MCP servers, shells, dev servers and test
  runners the agent spawned.
- **G2. Leftover detection and safe clean-up.** Find processes, listening ports and git worktrees that a
  session created and that outlived it, then let the user remove them with Mizu's safety rules.
- **G3. Live session state.** Show what each session is doing *now*: thinking, running a tool (and which one,
  for how long), waiting for permission, waiting for the user, compacting, or errored.
- **G4. Step-level inspection.** Provide one timeline per session that stacks turns, model calls and tool calls
  on the same time axis as cost and resource use. It also shows the agent's own plan or to-do progress and a
  deterministic one-line summary of each turn.
- **G5. Insights.** Raise deterministic alerts with evidence links: loops, error streaks, stalls, context
  pressure, cost spikes, runaway processes and leftovers.
- **G6. Log search.** Search across sessions and providers by tool, error, file, command and project. This
  includes the agents' own diagnostic logs.
- **G7. Traces and integrations.** Use one normalized trace model shaped like OpenTelemetry, with GenAI
  semantic-convention attribute names where they exist. Ingest OTLP/HTTP from agents and export OTLP to any
  collector the user picks: Langfuse, Phoenix, Grafana Tempo, Datadog and similar.
- **G8. Stay cheap.** Keep the monitor's own overhead below its budget (§12.2) and the upstream merge cost low.

### Non-goals (for this design)

- A hosted, multi-tenant SaaS backend or team aggregation. Teams get this by pointing the OTLP exporter at
  their own backend.
- Controlling agents: approving permissions, injecting prompts, pausing runs. The only actions are
  *terminating leftovers* and *removing clean worktrees*.
- Cloud-run agent sessions (Codex cloud tasks, Claude Code on the web) beyond what their OTLP export or
  provider APIs expose.
- Per-process GPU accounting. It needs root or private APIs on macOS; see §18.
- Any automatic LLM calls. LLM-assisted explanation is a later, explicitly opt-in feature (§9.4).
- Rewriting upstream's Spend pipeline. The cost ledger stays the source of truth for billing.

## 3. Requirements

### 3.1 Functional

| ID | Requirement | Pillar |
|---|---|---|
| F1 | Attribute every process an agent spawns to its session, including processes reparented after the agent exits | Resources |
| F2 | Sample CPU %, physical footprint, disk read/write bytes and energy per session tree; keep history | Resources |
| F3 | List listening TCP ports per session (dev servers) | Resources |
| F4 | Detect leftovers: processes, ports and worktrees from ended sessions, plus disk growth | Resources |
| F5 | Clean up leftovers with dry-run by default, explicit confirmation, SIGTERM before SIGKILL, and no forced worktree removal | Resources |
| F6 | Normalize Claude Code, Codex and (later) pi transcripts into sessions → turns → model calls / tool calls | Sessions |
| F7 | Derive live session state with ≤ 15 s lag from transcripts alone, or ≤ 3 s with hooks | Sessions |
| F8 | Extract plan progress from the agent's own planning tool (Claude `TodoWrite`, Codex `update_plan`) | Sessions |
| F9 | Summarize each turn deterministically: files changed, commands run (with failures), searches, tokens, cost, wall time | Sessions |
| F10 | Read message and tool bodies on demand only, with redaction and size caps | Sessions |
| F11 | Run detectors that produce insights with evidence (span IDs), severity and a suggested action | Insights |
| F12 | Deliver insights through the menu badge, macOS notifications and outbound `codexbar hooks` events | Insights |
| F13 | Search metadata and previews across sessions; full-content indexing is opt-in | Logs |
| F14 | Tail agent diagnostic logs (Claude Code debug logs, Codex TUI log, MCP server logs) as leveled events | Logs |
| F15 | Expose versioned `/telemetry/v1/*` read APIs and SSE; add CLI equivalents | Traces |
| F16 | Accept OTLP/HTTP JSON (`/v1/logs`, `/v1/metrics`, `/v1/traces`) and merge it with transcript-derived spans | Traces |
| F17 | Export OTLP to a user-configured endpoint with a bounded disk queue; exclude content by default | Traces |

### 3.2 Non-functional

| Area | Target |
|---|---|
| Privacy | Local-only by default. Nothing leaves the machine unless the user configures an exporter. Bodies are never persisted by default. Respects **Hide personal information**. Never reads other processes' environments. |
| Overhead | Collector averages < 0.5 % of one core and < 60 MB RSS with ≤ 10 live sessions at the "agents active" cadence. Zero sampling when no agent is live, apart from the 5-minute leftover sweep. |
| Freshness | Menu state ≤ 15 s (≤ 3 s with hooks). Console timeline ≤ 2 s for the selected session. |
| Query latency | `/telemetry/v1/sessions` p95 < 50 ms. A 1,000-turn session timeline loads in < 300 ms. Log search over 30 days p95 < 200 ms. |
| Storage | 1 GB default budget, user-adjustable. Full-fidelity spans for 14 days, turn summaries for 180 days, raw resource samples for 24 h, 1-minute rollups for 30 days. |
| Reliability | Ingest is idempotent: re-reading any source converges to the same rows. A crash loses at most the last unflushed batch of samples and never corrupts the store. Format drift fails soft and is reported as *partial coverage*. |
| Portability | Engine, CLI and API build on macOS 14+ and Linux. UI is macOS. Linux uses the CLI and the web UI. |

### 3.3 Constraints

- Fork rules (`AGENTS.md`): internal names stay `CodexBar*`. Prefer additive files. Keep diffs to upstream files
  minimal. Config paths stay `~/.config/codexbar` and `~/.codexbar`.
- Swift 6 strict concurrency and SwiftPM. **No new package dependencies** without sign-off (`VISION.md`).
  This rules out an OTLP protobuf library in v1 and drives decision D5.
- No checks or tests that can raise Keychain prompts. The telemetry engine needs no credentials at all,
  except for an optional exporter auth header.
- Cloud authoring sessions have no Swift toolchain, so every slice must be PR-sized and verified by macOS CI.
  Logic stays in pure, fixture-tested functions.
- Upstream treats on-disk transcript formats as *not* a public compatibility guarantee
  (`docs/agent-sessions-design.md`). The design must survive format drift.

### 3.4 Assumptions

- One user per machine, and only that user's own processes. Same-UID process inspection needs no special
  privileges on macOS or Linux.
- Typical usage is 1–3 concurrent agent sessions; a heavy user runs 10–30, counting subagents.
- Users who want push sources can opt in to editing `~/.claude/settings.json` (hooks) and `~/.codex/config.toml`
  (OTel).

## 4. What already exists (and gets reused)

Much of the substrate is already in the repo. The plan builds on it rather than replacing it.

| Capability | Existing code | Reuse in this design |
|---|---|---|
| Agent session discovery (Codex, Claude, pi/omp; local plus SSH/Tailscale) | `LocalAgentSessionScanner`, `PiFamilySessionScanner`, `AgentSession`, `RemoteSessionFetcher`, `codexbar sessions --json-v2` | Root PIDs and session identity for resource attribution; the remote pull pattern |
| Process inspection (libproc) | `DarwinProcessEnumerator`: `proc_listpids`, `PROC_PIDTBSDINFO` (ppid, start time), `KERN_PROCARGS2`, cwd, `PROC_PIDLISTFDS` | Process tree and port discovery; extend with `proc_pid_rusage` |
| Transcript cost ledger (SQLite, request de-duplication, fork/subagent coverage) | `Vendored/CostUsage/*` (`CostUsageScanner+Claude`, `+RequestIdentity`, `+ForkCoverage`), stored under `Caches/CodexBar/cost-usage/` | Stays the billing source of truth. Telemetry reuses its request-identity rules and pricing resolver. |
| Per-turn requests and turn performance (TTFT, duration, tokens/s) | `CostUsageSessionTurn`, `CostUsageSessionRequest`, `CostUsageTurnPerformance*` | Attributes on turn and model-call spans |
| Tool activity (Codex native, `event_msg/item_completed`) | `SessionToolActivityParser`, `SessionToolActivityStore`, `SpendSessionToolActivityView` | Seed of the Codex normalizer: identity rules, bounded projection, on-demand body reads |
| Per-provider disk footprint | `ProviderStorageFootprint`, `StorageBreakdownMenuView` | The "transcripts and caches" part of disk leftovers |
| Local HTTP server with token auth and Host allowlist | `CLILocalHTTPServer`, `CLIServeAuth`, `CLIServeCommand` (`/health`, `/usage`, `/cost`, `/dashboard/v1/snapshot`, web UI) | Mount `/telemetry/v1/*` and OTLP routes. Needs request-body parsing (§10.4). |
| Outbound automation | `Hooks/*` (`HookEventType`, `HookRunner`, `HookRateLimiter`), `codexbar hooks watch` | Deliver insights as new hook event types |
| Redaction and logging | `LogRedactor`, `CodexBarLog` | Redact previews and stored attributes |
| Model metadata | `ModelsDevPricing` (includes `contextWindow`) | The context-pressure detector |
| Power policy | `backgroundWorkLowPowerModeEnabled` in `SettingsStore` | Collector cadence clamps |
| Session browser and spend dashboard | `SessionUsageBrowser`, `SpendDashboard/*` | Entry points into the new Console session view |

## 5. High-level architecture

```
                            ┌───────────────────── Sources ──────────────────────┐
  zero-setup (pull)         │ ~/.claude/projects/**.jsonl   ~/.codex/sessions/**  │
                            │ ~/.pi/agent/sessions/**       agent debug/MCP logs  │
  OS (sampled)              │ libproc / /proc: process tree, rusage, sockets      │
                            │ git: worktree list / status                         │
  opt-in (push)             │ Claude Code hooks ─▶ `codexbar ingest hook` ─▶ spool│
                            │ OTLP/HTTP JSON (Claude Code, Codex, others)         │
                            └──────────────┬──────────────────────────────────────┘
                                           │
              ┌────────────────────────────▼─────────────────────────────┐
              │ CodexBarTelemetry engine (one writer, holds lease)       │
              │                                                          │
              │  Collectors                     Pipeline                 │
              │  ├ TranscriptTailer ─┐         ┌ Normalizers (per dialect)│
              │  ├ ProcessSampler   ─┼─ batch ─┤ Correlator (IDs, merge) │
              │  ├ FootprintScanner ─┤         ├ Interpreter (state, plan,│
              │  ├ SpoolDrainer     ─┤         │  turn summaries)        │
              │  └ OTLPReceiver*    ─┘         └ Detectors ─▶ Insights   │
              │                                        │                 │
              │                     TelemetryStore (SQLite WAL, 0600)    │
              │                     Retention / rollups / budget         │
              │                     Exporter* (OTLP out, disk queue)     │
              └───────────────┬───────────────────────────┬──────────────┘
                              │ read-only (WAL readers)   │
     ┌────────────────────────┼───────────────┬───────────┴──────────┐
     ▼                        ▼               ▼                      ▼
  Menu bar (macOS)       Console window    codexbar CLI        codexbar serve
  session rows, badges   Sessions/Resources trace, top,        /telemetry/v1/*, SSE,
  leftovers, insights    Logs/Insights      logs, cleanup       web UI, OTLP in*
                                                                 (* Phase 7)
```

**Hosts.** The engine is a library. It runs in-process in one of two hosts:

- **Menu bar app (macOS default).** It starts the collector when any telemetry feature is enabled.
- **`codexbar serve --collect` (Linux, headless, remote, and macOS when OTLP ingest is enabled).** This long-running
  process already exists. Phase 7 can register it as a per-user LaunchAgent (`SMAppService.agent`) or a systemd
  user unit for always-on collection.

**Single-writer lease.** The writer holds an exclusive non-blocking `flock` on `telemetry.lock` next to the
database. Any other host that finds the lock taken opens the database read-only and acts as a reader. The kernel
releases the lock when the writer crashes, and the next host to try takes over. Readers learn about changes from
`PRAGMA data_version` or `meta.revision`. Hook payloads never need the lease, because they go to an append-only
spool that the writer drains (§8.4).

**Store location.** The store holds data that cannot be rebuilt: resource samples, hook and OTLP events, and
insight history. It therefore lives outside Caches:

- macOS: `~/Library/Application Support/CodexBar/telemetry/telemetry-v1.sqlite`
- Linux: `${XDG_STATE_HOME:-~/.local/state}/codexbar/telemetry/telemetry-v1.sqlite`

The directory is `0700` and the files are `0600`.

## 6. Key decisions

Each decision lists the options, the choice, and what it costs.

**D1. Where the collector runs.**
Options:
- (a) In the app only.
- (b) A dedicated daemon from day one.
- (c) A host-agnostic library with a single-writer lease.

**Choice: (c).** It gives zero daemon work for Phases 2–6 and one code path for macOS and Linux. Collection
continues headless through `serve --collect`. A LaunchAgent becomes an incremental Phase 7 step, not a
prerequisite. *Cost:* lease handling and reader/writer roles. *Revisit* if always-on collection becomes the
default; the daemon then becomes the only writer.

**D2. Storage.**
Options:
- (a) Extend upstream's cost ledger.
- (b) A new SQLite database.
- (c) DuckDB or an embedded time-series database.

**Choice: (b).** SQLite is already linked (`CSQLite3`) and needs no new dependency. A separate file keeps
upstream's carefully migrated ledger untouched, which keeps merges cheap. *Cost:* two stores. Cost is not
copied into telemetry: model-call spans keep token counts and the request identity, and cost is resolved at
read time with the shared pricing resolver, so the two stores cannot disagree and price fixes apply
retroactively. *Revisit (c)* if month-scale analytical queries get slow.

**D3. Bodies (prompts, tool input and output).**
Options:
- (a) Copy them into the store.
- (b) Store a pointer: file fingerprint, byte offset and length.

**Choice: (b)** for transcript-sourced data. This mirrors the existing tool-activity contract: bodies are read on
demand, size-capped, redacted, and dropped when collapsed. OTLP and hook payloads have no file to point at, so
their content is **dropped by default**. When the user opts in to content capture, it is stored capped at
16 KiB per field. *Cost:* bodies vanish if the agent deletes its transcripts. That is acceptable and shown as
"source unavailable".

**D4. Trace model.**
Options:
- (a) A custom schema.
- (b) The OpenTelemetry span/log model with `gen_ai.*` attribute names where defined.

**Choice: (b)** internally, mapped at the export boundary. OTel GenAI semantic conventions are still marked
*development*, so the exporter pins a semconv version and keeps the mapping in one file. Fork-specific
attributes use a `sharingan.*` prefix.

**D5. OTLP wire format.**
Options:
- (a) JSON only.
- (b) JSON plus protobuf.
- (c) gRPC.

**Choice: (a).** OTLP/HTTP JSON needs no new dependency, and both Claude Code and Codex can be pointed at an
OTLP/HTTP endpoint. Verify each agent's JSON protocol option against its current docs during Phase 7. *Cost:*
clients limited to protobuf or gRPC cannot connect. Revisit with dependency sign-off when a real client needs it.

**D6. Interpretation.**
Options:
- (a) Deterministic state machine plus detectors.
- (b) An LLM summarizing steps.

**Choice: (a) first.** It costs nothing, runs instantly, gives the same answer every time, runs offline and
leaks nothing. The agents' own planning tools (`TodoWrite`, `update_plan`) already provide high-quality plan
state. (b) arrives in Phase 8 as an explicit, per-request, opt-in action with a payload preview.

**D7. Live updates.**
Options:
- (a) Polling.
- (b) File-system events.
- (c) Hooks/OTLP push.

**Choice: layered.** Poll every 15 s while agents are active, piggybacking on the existing session scan. Add a
vnode `DispatchSource` only for the session open in the Console. Use push sources when the user has opted in.
*Cost:* without hooks, "waiting for permission" can only be inferred (§9.1).

**D8. Destructive actions.** Clean-up is available **only** from the app UI and the interactive CLI, never from an
HTTP route, not even on loopback. *Cost:* the web UI cannot clean up, which is acceptable for v1.

## 7. Data model

### 7.1 Identity

| Entity | Key | Notes |
|---|---|---|
| Session | `session_key = host \| provider \| upstream_session_id` | `host` is `local` or the SSH destination. Matches `AgentSession.id` when resolved. |
| Trace | `trace_id = SHA-256(session_key)[0..16]` | Deterministic, so every source of the same session lands on one trace |
| Span | `span_id = SHA-256(trace_id \| kind \| natural_key)[0..8]` | `natural_key` is the turn ID, the de-duplicated request ID, or the tool call ID (`tool_use_id` for Claude, `call_id` for Codex) |
| Process | `(pid, start_time)` | Defeats PID reuse |
| External IDs | `attrs.sharingan.external.trace_id/span_id` | Agent-native OTLP IDs are kept for linking, never used as primary keys |

Deterministic IDs are what make ingest idempotent. The same tool call seen in a transcript, a `PostToolUse` hook
and an OTLP log record converges to one span. Each source fills the fields it knows, and `sources` becomes a
bitmask of all of them.

### 7.2 Span hierarchy

```
session (invoke_agent)                       trace root, one per agent session
├── turn                                     user prompt → final answer
│   ├── chat <model>                         one de-duplicated model request (tokens, TTFT, duration)
│   ├── execute_tool <name>                  tool_use/function_call → tool_result/output
│   │   └── (processes spawned during it)    linked by time window and lineage, not as spans
│   └── subagent (invoke_agent)              Claude sidechain / Task tool, Codex subagent rollout
│       └── … same shape, its own turns …
├── compaction                               context compaction boundary
└── events: permission.requested/decided, api.error, rate_limit, prompt.submitted, plan.updated
```

### 7.3 Schema (telemetry-v1)

```sql
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
  -- schema_version, revision, parser fingerprints, semconv version

CREATE TABLE sessions(
  session_key TEXT PRIMARY KEY, trace_id BLOB NOT NULL UNIQUE,
  host TEXT NOT NULL, provider TEXT NOT NULL, dialect TEXT, upstream_id TEXT NOT NULL,
  parent_session_key TEXT,                       -- subagent / fork lineage
  project_path TEXT, source TEXT,                -- cli | desktopApp | ide
  started_at INTEGER, ended_at INTEGER, last_activity_at INTEGER,
  live_state TEXT, live_state_since INTEGER, live_detail TEXT,   -- §9.1
  plan_json BLOB,                                -- latest TodoWrite/update_plan, capped
  coverage TEXT NOT NULL DEFAULT 'complete',     -- complete | partial:<reason>
  sources INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE spans(
  trace_id BLOB NOT NULL, span_id BLOB NOT NULL, parent_span_id BLOB,
  kind TEXT NOT NULL,            -- session | turn | chat | tool | subagent | compaction
  name TEXT NOT NULL,            -- 'chat <model>', 'execute_tool Bash', …
  start_ns INTEGER, end_ns INTEGER,
  status TEXT NOT NULL,          -- unset | ok | error | declined | unknown  (kept distinct, as in tool activity)
  attrs BLOB,                    -- JSON: gen_ai.* + sharingan.*, ≤ 8 KiB, redacted
  body_ref TEXT,                 -- 'file:<fingerprint>@<offset>+<len>' or NULL
  sources INTEGER NOT NULL,      -- bitmask: 1 transcript | 2 hook | 4 otlp
  PRIMARY KEY(trace_id, span_id)
) WITHOUT ROWID;
CREATE INDEX spans_by_time ON spans(start_ns);
CREATE INDEX spans_by_kind ON spans(kind, status, start_ns);

CREATE TABLE events(
  id INTEGER PRIMARY KEY, trace_id BLOB, span_id BLOB, ts_ns INTEGER NOT NULL,
  name TEXT NOT NULL, severity INTEGER, attrs BLOB, body_ref TEXT, source INTEGER NOT NULL,
  dedupe_key TEXT UNIQUE
);

CREATE TABLE turn_summaries(     -- kept 180 days after spans age out
  trace_id BLOB, turn_span_id BLOB, started_at INTEGER, ended_at INTEGER,
  input_tokens INTEGER, cached_input_tokens INTEGER, output_tokens INTEGER, reasoning_tokens INTEGER,
  tool_calls INTEGER, tool_errors INTEGER, files_changed INTEGER, lines_added INTEGER, lines_removed INTEGER,
  commands INTEGER, failed_commands INTEGER, headline TEXT,
  PRIMARY KEY(trace_id, turn_span_id)
) WITHOUT ROWID;

CREATE TABLE processes(          -- lineage: who started what
  pid INTEGER, start_ns INTEGER, session_key TEXT, root_pid INTEGER, first_ppid INTEGER,
  exe TEXT, argv_preview TEXT, cwd TEXT,          -- previews redacted, ≤ 256 chars
  attribution TEXT,                                -- confirmed | probable
  first_seen INTEGER, last_seen INTEGER, exited_at INTEGER,
  PRIMARY KEY(pid, start_ns)
) WITHOUT ROWID;

CREATE TABLE resource_samples(   -- raw, per session per tick, 24 h
  session_key TEXT, ts INTEGER, cpu_pct REAL, footprint_bytes INTEGER,
  disk_read_bytes INTEGER, disk_write_bytes INTEGER, energy_nj INTEGER, process_count INTEGER,
  PRIMARY KEY(session_key, ts)
) WITHOUT ROWID;
CREATE TABLE resource_rollups_1m(…same columns plus cpu_pct_max, footprint_max…);

CREATE TABLE listeners(pid INTEGER, start_ns INTEGER, proto TEXT, port INTEGER,
  first_seen INTEGER, last_seen INTEGER, PRIMARY KEY(pid, start_ns, proto, port));

CREATE TABLE leftovers(id TEXT PRIMARY KEY, kind TEXT,  -- process | port | worktree | disk
  session_key TEXT, subject TEXT, bytes INTEGER, detected_at INTEGER,
  state TEXT,                                            -- open | dismissed | cleaned | gone
  safety TEXT);                                          -- e.g. 'dirty-worktree', 'not-in-lineage'

CREATE TABLE insights(id TEXT PRIMARY KEY, session_key TEXT, detector TEXT, severity INTEGER,
  opened_at INTEGER, updated_at INTEGER, closed_at INTEGER, summary TEXT, evidence BLOB);

CREATE TABLE ingest_checkpoints(source_id TEXT PRIMARY KEY,
  file_identity TEXT,            -- dev:inode:size:mtime, as tool activity already checks
  byte_offset INTEGER, parser_fingerprint TEXT, coverage TEXT, updated_at INTEGER);
```

### 7.4 Source mapping

| Concept | Claude Code transcript | Codex rollout | Hook (Claude) | OTLP |
|---|---|---|---|---|
| Session | `sessionId` / file name | `session_meta` | `session_id` | `session.id` / `conversation.id` resource attrs |
| Turn | user text record → next user text record | `task_started` … `task_complete` (`turn_id`) | `UserPromptSubmit` … `Stop` | prompt event → next prompt |
| Model call | assistant records grouped by `requestId` (existing de-duplication rules), `message.usage` | `token_count` events, response items | — | api request events / metrics |
| Tool call | `tool_use{id,name}` → `tool_result{tool_use_id,is_error}` | `function_call{call_id}` → output; `item_completed` (existing parser) | `PreToolUse` / `PostToolUse` | tool decision / result events |
| Subagent | sidechain / subagent transcript records | subagent rollout shape (existing `CodexSubagentRolloutShape`) | `SubagentStop` | — |
| Plan | `TodoWrite` input | `update_plan` arguments | (same, via tool input) | — |
| Permission | inferred (§9.1) | approval events where present | `Notification` (permission prompt) | tool decision events |
| Compaction | compaction boundary records | compaction events where present | `PreCompact` | — |

Exact record and event names are dialect details owned by each normalizer and pinned by fixtures. The table
records *intent*. On-disk formats are not a public contract.

**Merge precedence** when several sources describe the same span:

- Timestamps: the transcript wins for completed spans, and hooks win for in-flight starts.
- Status: the most specific source wins. `error` and `declined` beat `unknown`.
- Token counts: only the transcript or ledger rules are used, never summed across sources.
- Content: only the transcript's `body_ref` is ever used.

## 8. Collectors

### 8.1 Transcript normalizers and tailer

- **Normalizers** are pure functions, `(dialect, bytes, checkpoint) -> [Record] + newCheckpoint + coverage`. There
  is one normalizer per dialect: Claude Code, Codex, then pi/omp. They reuse the cost scanner's request-identity
  and fork-coverage rules and the tool-activity parser's streaming projection, which skips arguments, outputs
  and diffs structurally. Unknown record types increment a counter and never throw.
- **Tailer.** On startup, an incremental backfill walks the same roots the cost scanner uses, bounded by the
  retention window. After that, each live session is tailed from its checkpoint. Before each read, the tailer
  checks file identity (`dev:inode:size:mtime`). A rewritten or truncated file triggers a full rescan of that file,
  because stale offsets are never trusted. Incomplete trailing lines are buffered until the next read.
- **Cadence** follows §12.2. The Console's selected session also gets a vnode `DispatchSource` on macOS, so updates
  are event-driven while it is visible.
- **Parser fingerprints** live in `meta`. When a normalizer changes, its affected files are re-derived lazily, newest
  first.

### 8.2 Process and resource sampler

Each tick runs these steps:

1. **Roots.** Take the agent PIDs from the latest `LocalAgentSessionScanner` result, which already runs on its own
   30 s cadence. Between scans, new agent processes are picked up by executable match during the full sweep.
2. **Descendants.** Walk each root's tree with `proc_listchildpids` on macOS, or `/proc/<pid>/task/*/children` and a
   `stat` ppid fallback on Linux. Cost scales with the tree size, not the machine's process count.
3. **Lineage.** Insert any `(pid, start_time)` not already in `processes`, with the session, the root and
   `attribution = confirmed`. Lineage is recorded *at first sight*, so when the agent exits and its children are
   reparented to launchd or init, they are still known to be the session's.
4. **Metrics.** On macOS, call `proc_pid_rusage(pid, RUSAGE_INFO_V4)`. It returns cumulative user and system CPU
   time, `ri_phys_footprint`, disk I/O bytes and billed energy. CPU % is ΔCPU / Δwall, using
   `mach_absolute_time` for wall time so that sleep is excluded. **Gotcha:** on Apple silicon the `ri_*_time` fields
   are in Mach time units, so convert with `mach_timebase_info`. On Linux, read `/proc/<pid>/stat` (utime, stime,
   starttime), `/proc/<pid>/status` (VmRSS) and `/proc/<pid>/io`. Energy is `nil` on Linux.
5. **Aggregation.** Write one `resource_samples` row per session per tick, and keep the top 5 processes per session in
   memory for the UI.
6. **Ports.** Every 15 s, walk each descendant's sockets: `PROC_PIDLISTFDS`, then `PROC_PIDFDSOCKETINFO` for TCP
   sockets in LISTEN state on macOS, or socket inodes matched against `/proc/net/tcp{,6}` on Linux. Results go to
   `listeners`.
7. **Full sweep.** Every 60 s, or every 5 minutes when no agent is live, run one `proc_listpids` pass. It updates
   `exited_at`, catches reparented leftovers, and marks *probable* attribution. A process is probable when its ppid
   is 1, its cwd is inside a live or recent session's project, its start time falls within that session, and it is
   not already known. Double-forking daemons whose intermediate process exits between ticks are the main reason the
   probable class exists. Probable items are never cleaned up without an extra confirmation step.

The sampler only ever inspects the user's own UID and never reads process environments. That matches
upstream's privacy rule. Argv previews go through `LogRedactor` and are truncated.

### 8.3 Disk footprint and clean-up

- **Leftover kinds:**
  - **process**: in the lineage, the session has ended, and it is still alive after a 10-minute grace period.
  - **port**: a listener owned by a leftover process.
  - **worktree**: `git worktree list --porcelain` for repos touched by the session's project, where either the
    worktree lies under known agent worktree roots or it was created during the session's lifetime.
  - **disk**: growth in transcripts and caches. This reuses `ProviderStorageFootprint` and is informational only.
- **Safety rules.** These are Mizu's rules plus a few of our own, and they are not configurable:
  1. Only items in the session's lineage are eligible. *Probable* items need a second confirmation.
  2. Every item is listed before anything happens. Dry-run is the CLI default (`codexbar cleanup` lists; `--apply
     <ids>` acts).
  3. Processes get SIGTERM, then a 5 s wait. SIGKILL needs a separate confirmation. Before signalling, the tool
     re-checks `(pid, start_time)` so that a reused PID is never hit.
  4. Worktrees are removed with `git worktree remove` **without `--force`**, and only after `git status --porcelain`
     comes back empty. A worktree with uncommitted changes is never eligible. If its branch is unmerged, the user
     sees a warning first.
  5. Transcripts are never deleted. "Reveal in Finder" is the only action offered for them.
  6. Every action is logged to the `leftovers` table (`state = cleaned`) and to `events`.
- Git runs through the existing `SubprocessRunner`, with timeouts and process-tree termination.

### 8.4 Hook ingest (Claude Code, opt-in)

- `codexbar ingest install-hooks --claude` adds `command` hooks for `SessionStart`, `UserPromptSubmit`, `PreToolUse`,
  `PostToolUse`, `Notification`, `PreCompact`, `Stop`, `SubagentStop` and `SessionEnd` to `~/.claude/settings.json`.
  It is idempotent, writes a timestamped backup, tags its entries with a marker, and `--uninstall` removes only the
  marked entries. The app exposes the same toggle.
- **The hook command must be invisible to the agent.** `codexbar ingest hook --source claude`:
  - reads stdin, which is capped at 1 MiB;
  - projects the payload to metadata: event, `session_id`, `transcript_path`, `cwd`, tool name, tool call ID,
    and input/output sizes and hashes;
  - appends one line to `spool/claude-<pid>-<date>.jsonl`;
  - prints **nothing** and always exits `0` within 50 ms.

  Printing nothing matters because stdout from some hook events is added to the agent's context. Tool inputs
  and outputs are dropped unless content capture is on.
- The writer drains the spool every tick, then deletes or rotates drained files. The spool is capped at 16 MiB.
  When it is full, the oldest file is dropped and a counter records the drop.
- Codex has no equivalent hooks in this design yet. Its `notify` program, which fires on turn completion, can feed
  the same spool. If Codex grows stable hooks, it gets an adapter.

### 8.5 OTLP receiver (Phase 7)

- `codexbar serve --collect --otlp` mounts `POST /v1/logs`, `/v1/metrics` and `/v1/traces`, accepting
  `application/json` only.
- The server binds to loopback by default. A non-loopback bind requires the existing bearer token, and the existing
  Host-header allowlist applies on every bind.
- Limits: 4 MiB per request body, a per-source token bucket, and `429` with `Retry-After` when limits are exceeded.
- Mapping is per known emitter (Claude Code, Codex) and keyed on resource attributes such as `service.name`.
  Unknown emitters still land as generic spans and events under a synthetic session per
  `service.instance.id`.
- Content attributes (prompt text and tool output) are dropped unless content capture is on.
- Setup helpers (`codexbar ingest configure --codex|--claude`) print or write the env and config lines for each agent.
  The `--write` variant is idempotent and makes a backup before editing.

## 9. Interpretation engine

### 9.1 Live session state machine

```
            prompt submitted / tool result appended
   ┌──────────┐ ─────────────────────────────────▶ ┌──────────┐ tool_use emitted ┌──────────────────┐
   │ waiting  │                                    │ thinking │ ───────────────▶ │ running_tool(n,t)│
   │ for user │ ◀───────────── Stop / turn done ── │          │ ◀─────────────── │                  │
   └──────────┘                                    └────┬─────┘  tool_result     └────────┬─────────┘
        ▲                                               │ compaction                      │ hook Notification
        │ SessionEnd / process exit                     ▼                                 ▼ (or inferred)
   ┌────┴─────┐                                    ┌──────────┐                  ┌──────────────────┐
   │  ended   │                                    │compacting│                  │awaiting_permission│
   └──────────┘                                    └──────────┘                  └──────────────────┘
   `errored`:  API error event / repeated failures (overlays any state until next progress)
   `stalled`:  detector overlay (§9.2), not a state
```

- **With hooks**, transitions are exact. **Without hooks**, `awaiting_permission` is inferred when four things hold:
  a `tool_use` has no result for more than 20 s, the tool is one that normally needs approval, process CPU is near
  zero, and no descendant was spawned. The UI labels this "probably waiting for approval". Upstream lists
  permission-waiting as an Agent Sessions non-goal, so this lives only in the fork's Console and menu additions.
- `live_detail` holds a short, redacted headline such as `Bash: swift test --filter Retry · 1m12s` or
  `Edit Sources/…/RetryPolicy.swift`.

### 9.2 Deterministic interpretation and detectors

**Interpretations** are always on, cheap and computed at ingest:

- **Plan tracker.** The latest `TodoWrite` or `update_plan` payload gives *n/m* done and the current in-progress
  item. That item becomes the session headline.
- **Turn summary.** Example: *"Edited 3 files (+120/−14), ran 5 commands (1 failed: `swift build`), 2 web searches ·
  $0.84 · 2m14s."* It is built from tool kinds, exit codes and diff stats where the dialect provides them.
- **Test runs.** Commands are matched against well-known test runners (`swift test`, `npm test`, `pytest`, `go test`,
  `cargo test`, `make test`). The pass/fail trend over the session is drawn as a small strip.
- **Files touched.** A per-session list of files with counts of edits and reads.

**Detectors** produce insights. Thresholds are defaults and configurable. Every insight stores the span IDs that
triggered it.

| Detector | Signal | Default trigger | Severity |
|---|---|---|---|
| Loop | Same tool plus normalized-arguments hash | ≥ 4× in one turn, or the same failing command ≥ 3× | warning |
| Error streak | Consecutive tool errors or non-zero exits that are not a search | ≥ 5 | warning |
| Stall | `thinking`/`running_tool` with no transcript growth and tree CPU < 1 % | > 5 min thinking; > 3× this tool's p95 | warning |
| Awaiting you | `awaiting_permission` or `waiting_for_user` while a turn is open | > 2 min | info, notifies |
| Context pressure | Last request's input tokens ÷ model `contextWindow`; compaction count | > 80 % or ≥ 2 compactions | info |
| Cache regression | Cached-input ratio falls below half the session median | 3 consecutive calls | info |
| Cost spike | Turn cost vs session median | > max($1, 3× median) | warning |
| Runaway process | A descendant's CPU or footprint | > 90 % for 5 min, or > 4 GB | warning |
| Leftover | Ended session's process, port or worktree still present | 10 min after end | info |
| Quota run-out | Existing pace/burndown projection | existing behavior | existing |

Insights open, update and close: they close when the condition clears or the session ends. Each one carries a
one-line suggested action, such as "Open session", "Show process", "Clean up…" or "Compact context". Nothing
acts automatically.

### 9.3 Delivery

- **Menu.** A badge on the session row, plus an "Insights" section that is hidden when empty.
- **Notifications.** Only `warning`, plus "Awaiting you". They are rate-limited per session and detector and
  reuse the existing notification plumbing.
- **Outbound hooks.** New `HookEventType` cases: `session_state_changed`, `insight_opened`, `insight_closed` and
  `leftover_detected`. They reuse `HookRunner` and `HookRateLimiter`, so users can route insights to Slack, ntfy or
  scripts without any new integration code.

### 9.4 Assisted explanations (Phase 8, opt-in)

"Explain this turn" or "Why did this fail?" works as follows:

1. The user explicitly chooses a provider and model, either an API key or their local CLI in headless mode.
2. The app shows the exact redacted payload, capped to the selected spans, before sending.
3. Each request has a spend cap.
4. Results are cached per span.

Nothing is ever sent automatically or in the background.

## 10. Interfaces

### 10.1 HTTP (served by `codexbar serve`, same auth model as `/dashboard/v1`)

| Route | Purpose |
|---|---|
| `GET /telemetry/v1/sessions?state=&provider=&since=&cursor=` | Session list with live state, headline, plan progress, cost so far, resource summary, open-insight count |
| `GET /telemetry/v1/sessions/{key}` | Detail: summary, plan, files touched, turn summaries, insights, top processes, listeners |
| `GET /telemetry/v1/sessions/{key}/trace?format=tree\|otlp` | Span tree, or OTLP-JSON `ResourceSpans` for direct import |
| `GET /telemetry/v1/sessions/{key}/events?after=` | Event page (cursor) |
| `GET /telemetry/v1/sessions/{key}/spans/{id}/body` | On-demand redacted body. `403` when Hide personal information is on; `410` when the source is gone. |
| `GET /telemetry/v1/resources?window=15m\|1h\|24h` | Per-session series (raw or rollup, chosen by window) |
| `GET /telemetry/v1/leftovers`, `GET /telemetry/v1/insights?open=true` | Read-only lists (no actions over HTTP: D8) |
| `GET /telemetry/v1/stream` | SSE: `session.state`, `insight.opened` / `insight.closed`, `resource.tick` |
| `POST /v1/logs\|metrics\|traces` | OTLP/HTTP JSON receiver (Phase 7, `--otlp`) |

Every response carries `Cache-Control: no-store`. Payloads carry `schema: "telemetry-v1"`. New fields are only
ever added; anything breaking goes in `/telemetry/v2`.

### 10.2 CLI

New commands are kept in new files and sit under existing namespaces where possible:

```
codexbar sessions inspect <id> [--json]          # state, plan, turn summaries, insights
codexbar sessions trace <id> [--format tree|json|otlp]
codexbar resources [--watch] [--interval 2]      # live per-session CPU/RAM/ports ("top")
codexbar cleanup [--apply <ids>] [--kill]        # dry-run by default
codexbar logs search <query> [--provider --since --errors --tool]
codexbar insights [--open] [--json]
codexbar ingest hook --source claude             # used by installed hooks; silent, exit 0
codexbar ingest install-hooks --claude [--uninstall]
codexbar ingest configure --claude|--codex [--write]
codexbar serve --collect [--otlp]
codexbar telemetry status|purge|export --otlp-endpoint <url> [--since 24h]
```

### 10.3 Export (Phase 7)

- **Where data goes.** The exporter pushes spans, events and resource metrics (as OTLP gauges) to one or more
  user-configured OTLP/HTTP JSON endpoints. Headers are configured per endpoint, and auth headers are stored
  with the existing credential storage, never in plain config.
- **Delivery.** Batches go out every 10 s or every 512 items. A bounded disk queue (64 MiB) absorbs outages.
  Retries use exponential backoff with jitter. When the queue is full, the oldest batches are dropped and the
  drop is counted.
- **What is sent.** Content is excluded by default. The setup screen shows a sample of exactly what will be sent.
- **Presets.** These are just endpoint and header templates, never SDKs: Langfuse, Arize Phoenix, Grafana Tempo or
  Alloy, and Datadog via an OTel collector.

### 10.4 Changes needed in existing serve code

`CLILocalHTTPServer` parses only the request line and headers. The OTLP receiver needs bounded body reads:
`Content-Length` capped at 4 MiB, no chunked encoding in v1, and a read deadline. The change should be one
additive body-reader helper plus a route hook, keeping the upstream diff small.

## 11. User surfaces

- **Menu (macOS).**
  - Agent session rows gain a state glyph and headline, CPU/RAM chips, cost so far, and an insight badge.
  - A new **Dev servers** subsection lists ports, with "Open localhost:port".
  - A **Leftovers** row reads "3 items · 1.2 GB · Clean up…" and is hidden when empty.
- **Console window.** A separate window, like Usage & Spend, with tabs: *Overview · Sessions · Resources · Logs ·
  Insights*. The session detail view is the core view: one time axis carries cost, steps and resources.

```
┌ api-server · Claude Code · running `swift test --filter Retry` 1m12s ──── $3.41 · ctx 62% ┐
│ Plan ▓▓▓▓▓░░ 5/7 ▸ Fix flaky retry test           Insights ⚠ Loop: same failing test ×3     │
├──────────────────────────── 14:02 ─────────── 14:10 ─────────── 14:18 ────────────────────┤
│ turn 11 ████████████████████                                                               │
│   chat    ██   ██    ██                                                                    │
│   Bash       ░░░░░░░░░░ swift build (48s)                                                  │
│   Edit                  ▌▌                                                                 │
│ turn 12                       ███████████████████████████▶                                 │
│   Bash                          ░░░░ ✗  ░░░░ ✗  ░░░░ ✗   swift test --filter Retry         │
│ CPU  ▁▂▇█▇▂▁▁▃▇██▇▃▁▇██▇▁▇██                                                                │
│ RAM  ▃▃▄▅▅▅▄▄▄▅▆▆▆▅▅▆▆▆▅▆▆                                                                │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│ Selected: Bash · exit 1 · 31s · [Show output] (on-demand, redacted)                        │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

- **Entry points.** The existing Usage & Spend session browser gets "Open in Console" from a session row, so that
  cost history leads straight into the step timeline.
- **Web UI** (`codexbar serve`). It gets the same Sessions and Resources views, read-only. This is the Linux and
  remote story.
- **Widgets.** A "Live agents" widget is deferred until the data model settles.

## 12. Scale, performance and reliability

### 12.1 Load estimates (single machine)

| Quantity | Typical | Heavy | Notes |
|---|---|---|---|
| Live agent sessions (incl. subagents) | 1–3 | 10–30 | |
| Processes per session tree | 3–15 | 50+ | MCP servers, shells, dev servers, test runners |
| Transcript bytes/day | 20–100 MB | 1–3 GB | Codex rollouts with big outputs dominate; projection skips bodies |
| Spans/day | 2k–10k | 50k–100k | |
| Span store, 14 days at ~0.5 KB/span | 15–70 MB | 350–700 MB | Default budget 1 GB; turn summaries are ~1/20 the size |
| Resource rows/day (5 s ticks while live) | ~10–50k raw | ~500k raw | Raw kept 24 h. 1-minute rollups for 30 days: 3–80 MB |
| Per-tick syscalls | ~50 | ~1,500 | `proc_pid_rusage` costs microseconds; 1,500 every 5 s is negligible |

These are planning estimates. Phase 2–3 performance gates replace them with measurements, following the
existing `CostUsagePerformanceGate` pattern.

### 12.2 Adaptive cadence (overhead budget)

| Condition | Process sample | Port scan | Transcript tail | Full sweep |
|---|---|---|---|---|
| Console open on a live session | 2 s (that session) | 15 s | event-driven | 60 s |
| Agents live | 5 s | 15 s | 15 s | 60 s |
| No live agents | off | off | 60 s | 5 min (leftovers) |
| Low power (app setting or macOS Low Power Mode) | 30 s | 60 s | 5 min | 30 min |

The collector measures its own `rusage` and reports it in Diagnostics. A performance gate fails CI if
synthetic-load overhead exceeds the §3.2 budget.

### 12.3 Retention and budget

- Raw samples are rolled up to 1-minute aggregates hourly.
- Spans and events older than 14 days are deleted after their turns are summarized.
- When the store is over budget, the oldest data goes first, with resources before spans before summaries.
- `auto_vacuum = INCREMENTAL` runs in small steps while idle.
- `codexbar telemetry purge` and a "Delete all telemetry" button remove everything.

### 12.4 Failure modes

| Failure | Effect | Mitigation |
|---|---|---|
| Transcript format drift | Missing spans or attributes | Unknown-record counters, `coverage = partial:<reason>`, fail-soft parsing, parser fingerprints and re-derivation; OTLP as a second source |
| File rewritten, truncated or rotated | Stale offsets | File-identity check before and after reads; rescan that file |
| Writer crash | Sample gap | Kernel releases the lease; the next host takes over; transcript backfill restores spans; gaps render as gaps, not zeros |
| Two hosts start at once | Contention | `flock` lease decides; the loser becomes a read-only reader; SQLite busy timeout |
| PID reuse | Misattribution or a wrong kill | `(pid, start_time)` identity everywhere; re-check before any signal |
| Sleep/wake | CPU % spikes | Δwall from `mach_absolute_time`, which stops during sleep; first tick after wake is discarded |
| Hook spool flood | Disk use | 16 MiB cap, oldest dropped, counter |
| OTLP flood / malformed input | CPU, memory | Body cap, token bucket, `429`; payloads are untrusted data (rendered as text, never executed) |
| Clock skew between sources | Out-of-order spans | Source timestamps used per source; future timestamps clamped to ingest time; merge by natural key, not by time |
| Store grows past budget | Disk | §12.3 eviction; Diagnostics warning at 80 % |

### 12.5 Monitoring the monitor

`/health` and Settings → Diagnostics show:

- lease holder;
- ingest lag per source;
- last sample time;
- parse errors and unknown records per dialect;
- spool backlog;
- exporter queue depth and drops;
- store size against budget;
- the collector's own CPU and RSS.

## 13. Security and privacy

- **Local by default.** No network egress unless the user configures an exporter or an assisted-explanation
  provider. Each one is opt-in, per destination, with a preview of what is sent.
- **No new secrets.** The engine needs no credentials. An exporter's auth header uses the existing credential
  storage.
- **Content minimization.** Bodies are pointers (D3). Hook and OTLP content is dropped unless the user opts in.
  Previews and attributes go through `LogRedactor`. Argv previews are truncated. Process environments are never
  read. Hide personal information disables previews and body reads, as tool activity already does.
- **Untrusted input.** Transcripts, hook payloads and OTLP bodies can contain attacker-influenced text, for
  example from web pages an agent read. That text is only ever rendered as text. It is never interpreted as
  commands, markup or links that open without a click.
- **Receiver hardening.** Loopback by default. Bearer token off-loopback. Existing Host allowlist (DNS-rebinding
  defense). Body and rate limits. No destructive routes (D8).
- **Editing other tools' config.** Hook and OTel setup only happens on explicit user action. It is idempotent,
  makes a backup first, and can be uninstalled.
- **Destructive actions.** The §8.3 safety rules are not configurable.
- **Files.** The telemetry directory is `0700` and its files `0600`. Purge removes the database, its WAL, the spool
  and the export queue.

## 14. Upstream merge strategy

Almost all new code goes in new places:

- `Sources/CodexBarTelemetry/`: a new target with the engine, store, collectors, normalizers, interpreter and
  detectors.
- `Sources/CodexBar/Console/`: the Console window and the menu section providers.
- `Sources/CodexBarCLI/Telemetry*.swift`: new commands and routes.
- `Tests/CodexBarTelemetryTests/`, plus portable tests mirrored into `TestsLinux/`.
- `docs/sharingan/`: fork-owned docs, this file included.

The upstream files that must change are kept to small seams:

| File | Change |
|---|---|
| `Package.swift` | Add the `CodexBarTelemetry` target and its test target; add dependency edges from `CodexBar` and `CodexBarCLI` |
| `CLIEntry.swift`, `CLIHelp.swift` | One dispatch line per new command namespace, delegating to new files |
| `CLIServeCommand.swift`, `CLILocalHTTPServer.swift` | A route hook for `/telemetry/v1/*` and `/v1/*`; a bounded body reader (§10.4) |
| `Hooks/HookEvent.swift` | Four new `HookEventType` cases |
| Menu composition / settings pane registry | One section provider and one settings pane registration |
| `DarwinProcessEnumerator.swift` | None. New libproc calls go in a separate file through an extension. |

Upstream's Agent Sessions design lists historical analytics, permission-waiting state and a persistent
remote daemon as non-goals. This design does the first two and offers an optional collector daemon, so it
should be treated as **fork-only**. If upstream later
wants pieces of it (the process sampler, the OTLP exporter), the module boundary makes them easy to offer.

## 15. Roadmap

Phases 2 and 3 share only session identity and the store. They can run as **parallel tracks**. Size is relative:
S, M or L.

| Phase | Scope | Size | Exit criteria |
|---|---|---|---|
| **2. Telemetry foundation** | `CodexBarTelemetry` target; store, lease, retention scaffolding; Claude Code and Codex normalizers; backfill and tailer with checkpoints; `codexbar sessions trace\|inspect`; turn summaries and plan tracker | L | Golden span trees for synthetic fixtures of both dialects. Re-ingest is idempotent, including shuffled, duplicated and truncated input. Cold backfill of 30 days of synthetic logs within a CI perf gate; incremental tick < 50 ms. Linux CLI tests green. |
| **3. Resources and clean-up (Mizu parity)** | Sampler for Darwin and Linux; lineage; rusage; ports; leftovers; worktree detection; `codexbar resources`, `codexbar cleanup`; menu chips, Dev servers, Leftovers | L | Overhead within budget under synthetic load. Mach-time conversion tested. Clean-up refuses dirty worktrees, PIDs not in the lineage, and reused PIDs (fakes). Real signals are never sent in tests. |
| **4. Session Inspector and live state** | Console window (Sessions tab, timeline, resource strip, plan, files, on-demand bodies); state machine; vnode tailing; opt-in Claude hook installer and spool | L | State latency ≤ 3 s with hooks and ≤ 15 s without, on fixtures with an injected clock. Hide personal information blocks bodies. Installer round-trips `settings.json` byte-for-byte on uninstall. |
| **5. Insights** | Detector framework; the §9.2 detectors; insight store; notifications; new hook event types; Insights tab | M | Every detector has positive and negative fixtures. Rate limiting tested. Thresholds configurable. |
| **6. Logs** | FTS5 over metadata and previews; tailing of agent diagnostic and MCP logs with level parsing; opt-in content index; Logs tab and `codexbar logs search` | M | p95 < 200 ms over a 30-day synthetic corpus. FTS5 availability verified for both the macOS system SQLite and the Linux `libsqlite3` (fallback: `LIKE` over previews). |
| **7. Traces and integrations** | OTLP/HTTP JSON receiver (`serve --collect --otlp`); Claude Code and Codex OTel mappers; exporter with disk queue and presets; `/telemetry/v1` frozen; web UI views; optional LaunchAgent or systemd unit | M | Round trip: transcript → OTLP export → OTLP ingest gives an identical trace. API contract tests. Receiver fuzzed with malformed JSON. |
| **8. Assisted explanations (optional)** | Opt-in "Explain this turn" with payload preview and spend cap | S | No request without explicit action. Preview equals the sent payload (test). |

Suggested first slices, each a separate CI-verified PR:

- **Slice 2a.** Target, store and lease, Claude normalizer, and `sessions trace` behind a hidden flag.
- **Slice 3a.** Sampler and lineage, with a `codexbar resources --json` read-out and no UI.

Both are useful alone. Together they unblock Phase 4.

## 16. Testing strategy

- **Fixtures.** The corpus is synthetic only: no real transcripts, and only released or clearly fictitious model
  names. One directory per dialect and version. Golden trace snapshots are JSON span trees with deterministic IDs.
- **Properties.** Ingest is idempotent: shuffling, duplicating and truncating input converges to the same result.
  Merge precedence holds across transcript, hook and OTLP sources. Retention never orphans spans.
- **Sampler.** It reads from an injected `ProcessSource` protocol, with a fake process table that supports PID reuse,
  reparenting and a sleep gap. Clocks are injected. The `ProcessTerminator` and git runner are injected, so tests
  never signal or touch real repos.
- **Store.** Tests use temp directories, cover lease contention between two in-process hosts, and recover after a
  simulated crash, reusing the `CostUsageStoreCrashHarness` approach. Performance gates follow
  `CostUsagePerformanceGateTests`.
- **No Keychain, no live agents.** Nothing in the telemetry tests reads credentials or real `~/.claude` and `~/.codex`
  data.
- **UI.** Model seams (`SessionInspectorModel`, `ResourcesPaneModel`) are tested without live `NSStatusBar` or
  `NSMenu`, per `AGENTS.md`.
- **Linux.** Normalizers, store, sampler (`/proc` backend against a fake procfs root) and the CLI run in `TestsLinux`.

## 17. Risks and open questions

**Risks.**

- **Format drift.** This is the biggest ongoing cost. Mitigations: fixture-per-version, fail-soft parsing, and
  coverage flags. OTLP is a second source that does not depend on file formats.
- **Scope.** "AIOps platform" can absorb unlimited work. The non-goals in §2 are the guardrail. Phases ship
  independently useful slices.
- **Overhead regressions** in a menu bar app. Mitigations: the CI performance gate and self-metrics in Diagnostics.
- **Misattributed clean-up.** Mitigations: lineage-only eligibility, extra confirmation for probable items, no
  `--force`, and re-checking `(pid, start_time)` before signalling.
- **Upstream churn** in session discovery and the cost scanner. Telemetry depends on a small, stable surface:
  `AgentSession` and the request-identity rules.

**Open questions for the owner.**

1. Is opt-in content capture (prompts and tool output stored locally for full-text search) wanted at all, or
   should Sharingan stay pointer-only forever?
2. Is installing Claude Code hooks, which edits `~/.claude/settings.json`, acceptable as an in-app toggle, or
   should it be CLI-only?
3. Should Phase 7's always-on collector (LaunchAgent) be offered, or must collection stop when the app quits?
4. Which trace backend matters first: Langfuse, Phoenix, Grafana, Datadog, or something else? This only changes
   presets.
5. How should remote hosts work: keep SSH pull (`sessions inspect --json` over SSH, no daemon), or allow a remote
   `serve --collect` with token-authenticated pull?
6. Should any of this be offered upstream? That decides whether new types carry fork-neutral names.

## 18. What to revisit as the system grows

- **Teams and multiple machines.** Don't build a server. Point the exporter at a shared OTLP backend, and add a
  read-only "team" view only if there is demand.
- **Protobuf or gRPC OTLP**, once a real client needs it (needs dependency sign-off).
- **Columnar analytics** (DuckDB, or Parquet export) if multi-month queries outgrow SQLite.
- **Remote collection.** Move from SSH pull to authenticated remote collectors that push.
- **GPU and local inference.** Per-process GPU on Apple silicon, plus Ollama and LM Studio resource attribution,
  once a non-root API is viable.
- **Cloud agents.** Cloud-run sessions, through provider APIs or OTLP if they offer them.
- **Daemon as sole writer**, if always-on collection becomes the default (D1).
- **Semconv.** Re-pin GenAI semantic-convention names when they become stable.
