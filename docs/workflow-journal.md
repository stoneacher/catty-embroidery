# Agentic workflow journal

Running log of how AI coding agents are used in this project: what was delegated, to which tool, what worked, what failed, and which guardrail (hook, CLAUDE.md rule, permission) was added in response. Raw data for the thesis methodology chapter — entries are short and dated; polish happens in the thesis, not here.

Entry template:

```
## YYYY-MM-DD — <short title>
- **Task**: what was attempted, and by which tool (Claude Code / Codex / manual)
- **Outcome**: worked / failed / partially — with the concrete evidence (tests, build, screenshot)
- **Adjustment**: rule/hook/process change made as a result (if any)
```

---

## 2026-07-07 — Initial agentic setup (Claude Code)

- **Task**: establish the agentic workflow before any implementation: hooks, MCP servers, docs, verification loops.
- **Setup decisions**:
  - Xcode project created with synchronized folder groups → agents create Swift files on disk, no `.pbxproj` edits ever needed; a permission rule additionally asks before any `.pbxproj` edit.
  - Hooks in `.claude/settings.json`: SwiftFormat on every edited Swift file (PostToolUse); engine `swift test` gate that blocks `git commit` when red (PreToolUse) — "never commit red" is now enforced, not requested.
  - MCP: XcodeBuildMCP (structured builds/tests/simulator/screenshots, user-scoped) + Apple's `xcrun mcpbridge` (docs/REPL; requires Xcode running).
  - Core loop per user story: plan mode → tests written and **proven red** → implement to green → independent review → commit.
  - Tool split: Claude Code for implementation (engine + anything touching ADR-012 semantics); Codex as independent reviewer and for mechanical batch tasks.
- **Friction encountered**: `brew install swiftformat swiftlint` failed — `/opt/homebrew` not owned by user; needs one-time `sudo chown -R stoneacher /opt/homebrew`. Formatter hook no-ops until then.

## 2026-07-07 — US-101 scaffold, one commit per acceptance step (Claude Code)

- **Task**: full US-101 (package, SwiftLint, CI, fixtures, license/README) as five commits on branch `US-101-project-scaffold-and-ci`; new user rules: no AI co-author trailers, branch named after story ID.
- **Outcome**: worked. Evidence: `swift test` green locally and in CI (pinned Xcode 26.6 = local toolchain, verified against the runner-image manifest before writing the workflow); SwiftLint 0 violations under `--strict`; fixture copies SHA-256-identical to Catty originals with a `Bundle.module` integrity test proven red (no `resources:` declaration) before green.
- **CI failure-path verification**: pushed a deliberate yoda-condition commit — lint job red, run concluded `failure` — then removed it. Note: the commit-gate hook makes a deliberately *failing test* uncommittable, so the red-CI check must use a lint violation; the hook itself ran on all five commits (first live uses, all green).
- **Friction encountered**:
  - SwiftFormat default (`--commas always`) fights SwiftLint's default `trailing_comma` rule; fixed by `--commas inline-only` in `.swiftformat` before they could ping-pong.
  - Plan was `git reset --hard` + force-push to drop the deliberate red commit; permission denied at the prompt → switched to `git revert` (append-only history, 7 commits instead of 5).
  - Xcode template files (snake_case type names) failed lint as errors; renamed types/files to CamelCase — safe because all three targets are synchronized folder groups (verified in `project.pbxproj` before renaming).
  - `gh` CLI absent; CI runs watched via unauthenticated GitHub REST API polling in background tasks instead (repo is public).
- **Adjustment**: none needed beyond the `.swiftformat` comma setting; existing hooks behaved as designed.

## 2026-07-07 — Fixture trust check: "empty" renders were correct (Claude Code + manual)

- **Task**: US-101's last criterion — verify the Catty golden fixtures render correctly in a named embroidery viewer (manual, Sebastian) with Claude Code diagnosing the results.
- **Outcome**: worked, but not as the criterion imagined. Every viewer showed *nothing*: EmbroideryViewer.xyz exported an all-transparent PNG (and a 0-byte PNG for the 50×0 mm design), Ink/Stitch found "no objects it knows how to work with". Diagnosis: the fixtures contain **no sewn segments** — only anchor stitches joined by jump records (moves > 12.1 mm interpolate to jumps), which viewers legitimately draw as nothing. Confirmed by decoding the record bytes with the inverse of Catroid's `CONVERSION_TABLE` (matches ADR-012's interpolation pattern and every header field) and cross-checked with pyembroidery 1.5.1, the parser inside Ink/Stitch. Verification recorded in the fixtures' `PROVENANCE.md`.
- **Agent failure worth noting**: the first quick decode used a DST bit table recalled from model memory — wrong — and produced a phantom "header/record mismatch" that looked exactly like the Catty bugs ADR-012 warns about. Deriving the decoder from the reference implementation's own table (instead of memory) dissolved it. Rule of thumb reinforced: for byte-level formats, never trust remembered tables; port the arbiter's.
- **Adjustment**: acceptance criteria phrased as "renders correctly in a viewer" need a fallback for degenerate test data; structural verification against the canonical encoder is the stronger form and is now the documented precedent.

## 2026-07-08 — Post-push CI gap closed with a hook; it caught two real bugs immediately (Claude Code)

- **Task**: US-102 was pushed and PR #2 opened without checking CI — Sebastian flagged the gap ("adapt your toolchain to also check the CI output after every push"). Added a PostToolUse hook on Bash in `.claude/settings.json`: any command containing `git push` injects a reminder into the model's context to watch the CI result (`gh pr checks --watch` / `gh run watch`) before treating the work as done.
- **Outcome**: hook verified end-to-end (pipe-test with synthetic payload, `jq -e` schema check, then a no-op `git push` that fired it live). Following the injected reminder immediately surfaced that **PR #2's CI was red**: 13 SwiftLint violations that local work never saw.
- **Root causes found while fixing**:
  - `.swiftformat` contained `--commas inline-only` — an **invalid option value**. SwiftFormat has been erroring out (exit 70) since US-101, so the PostToolUse format hook (which swallows errors) was a silent no-op. The US-101 journal entry recorded this value as the fix for the SwiftFormat/SwiftLint trailing-comma ping-pong; it "worked" only because it disabled the formatter. Correct value: `--commas never`.
  - No local SwiftLint step in the loop: violations (`x`/`y` identifier_name, `empty_count`, trailing commas) only surfaced in CI. Fixed the code, and allowlisted `x`/`y` in `.swiftlint.yml` (canonical coordinate component names, CGPoint precedent).
- **Adjustment**: push → watch CI is now hook-enforced, symmetric with the commit → engine-tests gate. Lesson recorded: a hook that suppresses a tool's errors (`|| true`) can hide a completely broken config for days — verify the wrapped tool runs clean, not just that the hook exits 0.

## 2026-07-08 — Push-after-every-commit rule; main branch protection (Sebastian + Claude Code)

- **New rule from Sebastian**: push to remote after every commit and watch CI, so problems surface immediately. The post-push hook gained a sibling: `git commit` now injects a "push now and watch CI" reminder (same PostToolUse hook, command-position match, verified by pipe-tests for commit-only / push-only / commit-and-push / unrelated).
- **Branch protection**: Sebastian set up a GitHub ruleset on the default branch (PR required before merging, block force pushes, restrict deletions). Review notes passed back before saving: "Restrict updates" with an empty bypass list would block even PR merges into main; "Require status checks to pass" (SwiftLint + engine tests) is the setting that actually gates merges on CI; "Require code quality results" blocks merges unless GitHub's code-quality analysis actually runs on PRs.

## 2026-07-08 — /finish session-close command added (Claude Code)

- **Task**: Sebastian asked for a `/finish` slash command that verifies session-end hygiene: DECISIONS.md / ROADMAP.md / workflow-journal.md reflect the session, and the current story's acceptance criteria are verified-then-ticked with a Done status line. Created as `.claude/commands/finish.md` (committed, transfers with the repo).
- **Design guardrail**: the command's checklist is verify-then-update — criteria may only be ticked against evidence (tests/CI), ADRs only for genuine decisions, no content invented to satisfy the checklist.
- **Outcome**: dry-ran the checklist on this session: US-102 marked Done (all criteria evidenced, PR #2 CI green); no ADR or roadmap change warranted; journal was already current.
