---
name: longrun
description: Run tasks that must execute and be supervised continuously for more than a few hours (up to and beyond 24h). Use when the user asks for long-haul, overnight, unattended, 24h+, "跑一整天" or continuous monitoring work — settling mission goals, checkpointed lanes, scheduled checks, and crash recovery.
---

# Long-haul (>24h) execution & monitoring patterns

Read this fully before accepting a long-haul assignment. The governing principle:
**never rely on one uninterrupted process or one infinite context**. Every layer must
assume that it will be interrupted at the worst moment, and be re-derivable from durable state.

## Layer 1 — Process survival

- Run the Pi session inside **tmux** (`extended-keys` is already configured in `~/.tmux.conf`)
  so terminal/SSH disconnects do not kill the session: `tmux new -s longrun pi`.
- Sessions persist automatically (never `--no-session` for long-haul). If the shell dies,
  recover with `pi --continue` (or `--resume` picker) from the same cwd, then complete
  recovery from Layers 2–4.
- Set an explicit schedule first if monitoring windows are predictable; see Layer 3.

## Layer 2 — Mission as the recovery backbone

Ordinary task launches auto-create a mission record (durable, survives compaction and restart).

- Substantial long-haul work: state the goal explicitly in the launch, and register the
  mission id in your first assistant message so the human has the handle.
- For "keep working toward this goal until done, budget X" use a goal mission:
  mission: { title: "...", objective: "...", goal: true, budget: { tokens: <cap> } }
  It nudges the session at idle turns until budget exhaustion; close with
  `mission.close` when done (goal notices never self-close).
- Steer continuation through mission state, not chat history:
  `state.set("nextReadyAction", "…")` — after compaction/restart, the notice names this step.
- Keep state small (paths, not contents). Durable finds go to mission artifacts (`review`,
  `note`, `patch`) or child `output` files, referenced by path.
- Record receipts (PR/CI/deployment links) with `mission.update`; receipts are evidence only.
- Recovery after any context loss: `mission.list` → `mission.show <id>` → rehydrate the board
  from linked run statuses and mission state before writing anything.

## Layer 3 — Scheduled checks (monitoring backbone)

`schedule.create` persists a durable workflow schedule independent of the Pi process:

- One-shot ping: `at: "+30m"`; recurring: `every: "30h"/"6h"/...` with `catchUp: "latest"` for gaps.
- Keep schedules outside the repo: this machine uses storeRoot `~/.pi/subagent-schedules`.
- A scheduled workflow launches async with fresh context; do light probe work inside it
  (read-only status grep, log tail check) and have it record findings to mission state or
  `mission.update`, so the human's interactive session only consumes deltas.
- Inspect: `schedule.list`, `schedule.show`, `schedule.history`: misfired runs are visible
  in history; `schedule.run` forces one now; `schedule.pause`/`resume` for maintenance windows.

## Layer 4 — Checkpointed async lanes, not mega-runs

- Default per-child runtime deadline is 2h (config `timeoutMs: 7200000`); a
  checkpoint steer arrives ~10 min before any deadline and the child stops gracefully —
  respond to checkpoint reports instead of treating them as failures.
- For a genuinely long child (e.g. an overnight monitor), pass an explicit per-call budget:
  `timeoutMs` up to 90000000 (25h) and `control: { needsAttentionAfterMs: 1800000, notifyOn: ["needs_attention"] }`
  for long silent stretches; a child surfaced as needs_attention was *observed* idle, not proven stuck.
- Prefer `resume` chains over one giant run: each resumed child continues the same child
  session from its persisted file, so 4 × 6h legs inherit full continuity with bounded blast radius.
- Use `agent: "longrun-monitor"` for watch/report loops; it enforces bounded commands and
  checkpoint files. Retained completed children are resumable via workflow receipts
  (`resume: { workflowRunId, key, latest: true }`) — never re-dispatch from scratch when a
  receipt exists.
- Wait correctly: ordinary async children notify the parent natively — yield and let Pi wake
  the session. Only detached non-notifying work needs `bg_wait({ id, nonBlocking: true })`
  subscriptions. Blocking `bg_wait` windows default to 1h here (`waitTool.defaultTimeoutMs`).

## Budget guardrails

- 600 spawns per session (visible in `status`/`doctor`; interactive grant possible),
  8 concurrent async lanes, 64 per-run tree. Treat near-limit readings as a prompt to
  consolidate probes into scheduled runs or fewer bigger lanes, not as provider failure.
- Run `/subagents-doctor` (or `subagent({ action: "doctor" })`) whenever extension setup,
  orphaned panes/slots, or double-delivery is suspected — before reinstalling anything.

## Maintenance rituals during a long haul

- **Health every few wake-ups:** `subagent({ action: "status" })` fleet view; glance at
  watchdog journal notices; observability dashboards if observ-pi is running.
- **Compaction hygiene:** context threshold auto-compacts at ~76% of the 1M window with 64K
  recent retention. During a lull, `/compact` with instructions preserving open mission ids,
  pending gates, and next steps is cheap insurance before heavy phases.
- **Session hygiene:** `/session` occasionally for entry/token drift; near-window compaction
  chosen by config, don't fight it.
- **Disk/session-file hygiene on multi-day runs:** verify `~/.pi/agent/sessions` growth and
  prune old sessions via picker if disk pressure appears.

## Quick start recipes

- **Overnight build & fix:** goal mission (budget) + `worker` lane (2h deadline, checkpoint
  before deadline) + scheduled "is CI green / lane attention" check every 1–2h reporting to mission state.
- **Multi-day watch (migration / soak):** `schedule.create` every 6h running `longrun-monitor`
  probes via a fixed-role workflow; probes write mission `state` deltas; human session closes
  mission at morning triage.
- **Burst fanout now, resume resumes later:** `runs.all([...])` lanes with distinct keys and
  per-lane output paths; failed lanes: read summary, adjust task, `resume` by key from receipt.