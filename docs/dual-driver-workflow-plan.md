# Dual-driver workflow: make Claude Code and Codex CLI interchangeable as "main driver"

**Status:** parked — design only, not yet implemented. Pick up in a future session outside current milestone story work.

## Context

The project's agentic workflow is currently built one-directionally: Claude Code drives (writes code, runs the TDD gate, delegates to the `swift-engineering` plugin's subagents), and Codex CLI is invited in only as an independent cross-vendor reviewer (`/codex-review`). `AGENTS.md` exists and is meant to mirror `CLAUDE.md` for Codex, but today it's a *reduced* document — it drops the hook mechanics, the subagent roster, and the driver-side process detail, because none of that had a Codex equivalent when it was written.

The concern driving this change: if this project is handed to a future maintainer (e.g. after transfer to the Catrobat org) who doesn't have a Claude subscription, they should be able to drive the exact same TDD/ADR-arbitrated workflow with Codex instead, with Claude flipping into the reviewer role — without losing the enforcement (test-gate, formatting) or the specialized subagent delegation that makes the Claude-driven workflow work today.

Research done while designing this (via `codex features list` on the actual installed CLI, and OpenAI's current docs at `developers.openai.com/codex/*`) found the assumption "Codex has no hooks/subagents" is **outdated**. Codex CLI (checked at v0.144.0) has three stable primitives that map directly onto the Claude Code mechanisms this repo already depends on:

| Claude Code mechanism | Codex CLI equivalent |
|---|---|
| `.claude/settings.json` `PreToolUse`/`PostToolUse` hooks (matcher, command, exit-code-2 blocks) | `.codex/config.toml` `[[hooks.PreToolUse]]`/`[[hooks.PostToolUse]]` — same matcher/command/timeout/exit-code-2-blocks schema, gated on the project being "trusted" (same trust-on-first-use model Claude has) |
| `swift-engineering` plugin subagents (`.md` agent defs with tool restrictions) | `.codex/agents/*.toml` — one file per project-scoped custom agent, with `name`/`description`/`developer_instructions`/`model`/`sandbox_mode` |
| `.claude/skills/` (or `.claude/commands/`) `SKILL.md`/slash-commands | `.agents/skills/<name>/SKILL.md` — same open `SKILL.md` frontmatter format (`name`+`description`) that Anthropic open-sourced and OpenAI adopted for Codex; invoked via `/name` or `$name` |

So genuine feature parity (not just documentation parity) is achievable. This plan designs a **symmetric dual-driver setup**: both `.claude/` and `.codex/`+`.agents/` toolchains live in the repo permanently, kept at parity, sharing the same underlying scripts where possible. There is no "mode switch" — a maintainer simply runs whichever CLI they have access to; that CLI's own project config takes over transparently, and the other vendor is available as the cross-vendor reviewer either way. The only script needed is a one-time bootstrap, not a mode-switcher.

This is a tooling/process change, not a user story — per existing convention ("tooling fixes don't get ADRs"), it stays out of `docs/DECISIONS.md` and lives in `CLAUDE.md`/`AGENTS.md`/`docs/workflow-journal.md`, same as the current Claude/Codex split does today.

## Target design

### 1. Shared scripts (new: `scripts/hooks/`, `scripts/review/`)

Pull the logic that's currently inlined as one-liners in `.claude/settings.json` out into standalone scripts, so both vendors' hook systems call the *same* code:

- `scripts/hooks/test-gate.sh` — today's "never commit red" logic: on `git commit`, unless the message contains `[red]`, run `swift test` inside `Packages/EmbroideryEngine`; block (non-zero exit) with the failure tail if red.
- `scripts/hooks/format-swift.sh <file>` — today's SwiftFormat PostToolUse logic, extracted to take a file path argument.
- `scripts/review/cross-vendor-review.sh <self>` — generalizes `.claude/commands/codex-review.md`'s body. Given `self` (`claude` or `codex`), shells out to the *other* vendor's headless review invocation against `git diff main...HEAD`, pointed at the same ADR-012/013/017-aware adversarial rubric used today:
  - `self=claude` → `codex exec -s read-only -C "$PWD" -o /tmp/codex-review-verdict.md "<rubric>"` (today's exact invocation, unchanged).
  - `self=codex` → `claude -p --permission-mode plan --allowedTools "Read Grep Glob Bash(git *)" "<rubric>"` (new — confirmed flags exist: `-p/--print` for non-interactive output, `--permission-mode plan` for a read-only-equivalent session, `--allowedTools` to scope it to inspection).
  Same triage rule applies regardless of direction: ADRs are the arbiter, findings that contradict a pinned ADR are invalid, verdict gets appended to the PR description and journaled, re-review rounds run on branch changes (cap 3).

### 2. Claude side (adjust existing files to call the shared scripts)

- `.claude/settings.json`: point the existing `PreToolUse`/`PostToolUse` hooks at `scripts/hooks/test-gate.sh` / `format-swift.sh` instead of inlining the logic — no behavior change, just de-duplication so Codex's hooks can reuse the same scripts.
- `.claude/commands/codex-review.md` (or migrated to `.claude/skills/codex-review/SKILL.md` — verify during implementation which the installed Claude Code version actually resolves `/codex-review` from) becomes a thin wrapper calling `scripts/review/cross-vendor-review.sh claude`.
- `swift-engineering` plugin agents remain Claude's subagent roster, unchanged.

### 3. Codex side (new — mirrors Claude 1:1 using Codex's real primitives)

- `.codex/config.toml`:
  ```toml
  [[hooks.PreToolUse]]
  matcher = "Bash"
  [[hooks.PreToolUse.hooks]]
  type = "command"
  command = "scripts/hooks/test-gate.sh"

  [[hooks.PostToolUse]]
  matcher = "apply_patch|Edit|Write"
  [[hooks.PostToolUse.hooks]]
  type = "command"
  command = "scripts/hooks/format-swift.sh"
  ```
  (exact matcher name for Codex's file-edit tool — `apply_patch` vs `Edit`/`Write` — needs a quick check against the installed Codex version during implementation; docs list all three as valid matcher targets.)
- `.codex/agents/*.toml` — one file per subagent needed to drive a story, ported from the `swift-engineering` plugin's existing prompts into Codex's schema (`name`, `description`, `developer_instructions`, `model`, `sandbox_mode`):
  - `swift-architect.toml` (planning)
  - `swift-code-reviewer.toml` (post-implementation review, `sandbox_mode = "read-only"`)
  - `swift-documenter.toml` (milestone-end docs)
  - `swift-engineer.toml` (green-phase implementation against already-red tests only — same delegation boundary as today)
  Deliberately **not** ported, same rationale as the current Claude-side rule: `swift-test-creator` (story tests are never delegated — least-delegable work in the repo), `tca-architect`/`tca-engineer` (ADR-006: no TCA), `swift-modernizer` (greenfield, nothing to modernize). `swift-ui-design`/`swiftui-specialist` deferred until M3 (not needed yet on either vendor).
- `.agents/skills/claude-review/SKILL.md` — Codex's mirror of `/codex-review`, calling `scripts/review/cross-vendor-review.sh codex`.
- `.agents/skills/finish/SKILL.md` — Codex's mirror of `/finish`'s session-end checklist. If the installed Claude Code version also resolves skills from `.agents/skills/` (it's the same open format Anthropic authored — verify during implementation), this can be the *one* canonical file instead of two copies.
- `AGENTS.md` gains back the sections it currently drops relative to `CLAUDE.md`: the subagent roster and when to use each (pointing at `.codex/agents/*.toml`), the hook mechanics (now real, described as such rather than as manual process), and an explicit "this is the Codex-as-driver playbook, mirroring CLAUDE.md's Claude-as-driver playbook" framing.

### 4. Bootstrap script (new: `scripts/setup.sh`)

Not a mode-switcher — a one-time per-maintainer setup step:
- Check `swiftformat`/`swiftlint` are on `PATH` (warn, don't fail, matching today's hook no-op-if-missing behavior).
- If `codex` is installed: trust the project non-interactively so `.codex/` project layers (hooks, agents) actually load — Codex ignores project-local `.codex/` config for untrusted projects. Likely `codex -c 'projects."'"$(pwd)"'".trust_level="trusted"'` (verify exact flag during implementation against the config.toml `[projects."<path>"] trust_level = "trusted"` shape confirmed in this session).
- If `claude` is installed: no trust automation needed (Claude prompts once interactively); just confirm `.claude/settings.local.json`'s reference-repo `additionalDirectories` entry exists.
- Print a short "you're set up to drive with `<vendor>`" message pointing at the right root doc.

### 5. Docs & journal

- No new ADR (tooling, not a domain/architecture decision — consistent with today's convention).
- Once implemented: one `docs/workflow-journal.md` entry describing the parity work, citing the Codex primitives discovered (hooks, subagents, skills) as provenance, and noting this plan's parked-then-implemented lineage (same pattern as the earlier "Codex plan review" idea that was parked before maturing into ADR-014).
- Reinforce in `/finish`'s checklist (and its Codex mirror): a process-rule change to `CLAUDE.md` must be mirrored into `AGENTS.md` in the same session — called out explicitly because `AGENTS.md` was already found silently out of sync once (2026-07-10).

### Explicitly out of scope for this plan (accepted, not solved)

- No generator/single-source-of-truth tooling to keep `.claude/agents/*` and `.codex/agents/*` in sync automatically — they're hand-authored in parallel because the schemas differ (Claude plugin `.md` vs Codex TOML). A future nice-to-have, not required now.
- Whether Codex's sandboxed `mcp_servers` config can drive the same XcodeBuildMCP tool calls (sim build/test/screenshot) Claude uses today is unverified — flag it as a spike for whoever implements the M3+ UI-story agents on the Codex side.

## Critical files (for the future implementation session)

- `.claude/settings.json` — hooks to de-duplicate into `scripts/hooks/`
- `.claude/commands/codex-review.md`, `.claude/commands/finish.md` — become thin wrappers over shared scripts
- `AGENTS.md` — gains the dropped sections back, framed as the Codex-driver mirror of `CLAUDE.md`
- `CLAUDE.md` — gains a short cross-reference note pointing at `AGENTS.md`/`.codex/` as the equivalent Codex-driver setup
- New: `scripts/hooks/test-gate.sh`, `scripts/hooks/format-swift.sh`, `scripts/review/cross-vendor-review.sh`, `scripts/setup.sh`
- New: `.codex/config.toml`, `.codex/agents/{swift-architect,swift-code-reviewer,swift-documenter,swift-engineer}.toml`
- New: `.agents/skills/claude-review/SKILL.md`, `.agents/skills/finish/SKILL.md`

## Verification (for the future implementation session)

- Trigger the ported test-gate under Codex: make a failing engine test, attempt `git commit` from a Codex session, confirm it's blocked with the same failure-tail output Claude's gate produces; confirm `[red]` in the message still bypasses it.
- Confirm SwiftFormat runs after a Codex-driven edit (check the file is reformatted after `apply_patch`/`Edit`).
- Run `.agents/skills/claude-review/SKILL.md` (i.e. `$claude-review` or `/claude-review` in a Codex session) against a real branch diff and confirm it produces a verdict via `claude -p`, and that the triage-against-ADRs rule is followed the same way `/codex-review` does today.
- Spawn one ported subagent (e.g. `.codex/agents/swift-code-reviewer.toml`) in a Codex session and confirm it produces review output scoped by its `sandbox_mode = "read-only"` restriction.
- Confirm `scripts/setup.sh` run on a fresh clone actually gets `.codex/` project hooks/agents loading (no silent "untrusted project, ignoring .codex/" behavior).
