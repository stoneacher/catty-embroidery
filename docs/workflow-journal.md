# Agentic workflow journal

Running log of how AI coding agents are used in this project: what was delegated, to which tool, what worked, what failed, and which guardrail (hook, CLAUDE.md rule, permission) was added in response. Raw data for the thesis methodology chapter — entries are short and dated; polish happens in the thesis, not here.

**Append-only** (rule from Sebastian, 2026-07-10): existing entries are never edited or amended — the unrevised record, including mistakes and wrong first attempts, is the data. To correct something an earlier entry got wrong, append a new dated entry referencing it.

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

## 2026-07-08 — /finish gains an explicit Ink/Stitch manual-check callout (Sebastian + Claude Code)

- **New rule from Sebastian** (after merging PR #2): story completion must state explicitly whether a manual check with the Inkscape embroidery plugin (Ink/Stitch) is needed — automated green isn't proof of what a machine will sew (the US-101 "empty fixtures" episode is the precedent). Added as step 5 of `/finish`: name the file/design to open and what to look for, or state explicitly that no check is warranted.

## 2026-07-08 — Red-phase commits made visible in CI via a [red] marker; classifier blocked the agent's hook edit (Sebastian + Claude Code)

- **Task**: US-103 planning — Sebastian asked for the failing tests to be *committed and pushed* so the TDD red phase is visible in the pipeline, not just locally. This conflicts with the never-commit-red PreToolUse gate (US-102 era), which runs the engine tests before every `git commit` and blocks on failure.
- **Outcome**: gate amended rather than removed — a commit whose message contains a literal `[red]` marker skips the test run; everything else stays gated. Notable friction: Claude's first attempt to edit `.claude/settings.json` was **denied by the permission classifier** as self-modification of a user-established safety hook ("only the agent's own plan claims the user wants this"). The plan approval wasn't legible to the classifier as authorization. Resolved by asking Sebastian explicitly (AskUserQuestion) and retrying after his answer.
- **Adjustment**: TDD red commits are now a first-class, self-documenting act (`… [red]` in the message, red CI run on the branch); branch protection still keeps red out of `main`. Lesson: an agent weakening its own guardrail needs user authorization *at the moment of the edit* — a previously approved plan isn't enough for the permission layer.

## 2026-07-08 — Swift Testing exit tests: no context capture, and a compiler crash (Claude Code)

- **Task**: US-103 — test the encoder's ±121 `precondition` with Swift Testing exit tests (`#expect(processExitsWith: .failure)`), first written as a parameterized `@Test(arguments:)` whose exit body used the case's delta.
- **Outcome**: failed twice in one build: an exit-test body runs in a fresh process and must not capture context ("a C function pointer cannot be formed from a closure that captures context"), and the construct then **crashed swift-frontend 6.3.3** (SendNonSendable pass, `error: fatalError`). Workaround: one non-parameterized test with four exit expectations using only literal deltas — green.
- **Adjustment**: none needed beyond the pattern; noted here since exit tests will recur (US-105 interpolation invariants).

## 2026-07-08 — Permission classifier blocks self-merge of the agent's own PR (Claude Code)

- **Task**: US-103 close-out — the approved plan said "merge when green", so Claude attempted `gh pr merge 4` after checks passed.
- **Outcome**: denied by the auto-mode classifier as merge-without-review/self-approval, same shape as the settings.json denial earlier this session: plan-level approval is not action-level authorization. PR #4 left green and unmerged for Sebastian.
- **Adjustment**: Sebastian made it a standing rule right after: the agent must **never attempt a PR merge** — he always merges manually, regardless of what a plan says or how green CI is. A story ends with a green PR and its link handed over.

## 2026-07-09 — OpenSpec evaluated and rejected (Sebastian + Claude Code)

- **Task**: Sebastian asked whether adopting OpenSpec (Fission-AI's spec-driven-development framework: `/opsx:propose` → `proposal.md`/`specs/`/`design.md`/`tasks.md` under `openspec/changes/`, then apply and archive) would make sense for this repo.
- **Outcome**: rejected as redundant. Every OpenSpec artifact already has a project-native equivalent: proposal ≈ user-story header (story, epic, estimate, dependencies), specs ≈ acceptance-criteria checklists, design ≈ DECISIONS.md ADRs, tasks ≈ the stories' "Test-first plan" sections — which are better fitted here because they encode TDD ordering, which OpenSpec's generic task lists don't. Additional costs: a Node 20 tool dependency and tool-specific `openspec/` tree in a Swift repo headed for Catrobat handover; a mid-milestone format switch (M1 fully specced, three stories done); and a process change partway through the thesis measurement period.
- **Adjustment**: no tooling adopted. One practice borrowed without the tool: OpenSpec's *explore-before-propose* step — for M2+ milestones, hold a short exploratory session with the agent before writing the stories, captured as an ADR or milestone README.

## 2026-07-09 — Red-phase CI run doubled as an early lint gate (Claude Code)

- **Task**: US-104 — DST header writer, standard red→green flow (stub + failing tests committed `[red]`, PR #6).
- **Outcome**: the deliberately-red CI run surfaced a **SwiftLint violation** (`optional_data_string_conversion` in the test-side header parser) alongside the expected test failures — SwiftLint runs only in CI, so pushing the red baseline caught it before the green commit was even written; fixed in a one-line follow-up and the PR went green. Otherwise the smoothest story so far: both golden headers matched the fixtures byte-for-byte on the first implementation attempt, largely because the plan phase hexdumped the fixtures and pinned the padding bytes before any code was written.
- **Adjustment**: none needed; noted that pushing the `[red]` commit has a second benefit beyond documenting the baseline — it runs the linters on the new test code early.

## 2026-07-09 — US-105: story-spec miscount caught in planning; external branch switch mid-session (Claude Code)

- **Task**: US-105 long-move interpolation, standard red→green flow (PR #7).
- **Spec bug caught by plan-phase reference reading**: the story's test-first plan said a 122-unit move emits 3 records; both references (and the story's own acceptance criterion) emit 4 — `splitCount = ceil(122/121) = 2` produces a midpoint intermediate. Verified against Catroid `DSTStreamTest.testInterpolatedStitchPoints` before any test was written; the story line was corrected in the same PR. Reading the reference *tests*, not just the implementation, during planning is what caught it.
- **Incident — external branch switch**: 9 seconds after the agent created `US-105-interpolation-and-jumps`, something outside the session checked the repo back out to `main` (reflog: `checkout: moving from US-105-interpolation-and-jumps to main`, 17:25:36); the `[red]` commit consequently landed on local `main` and the first branch push went out without it. No hook does this — cause unknown (another terminal/tool acting on the checkout). Recovered via reflog: `git branch -f` moved the commit to the story branch, local `main` reset to `origin/main` (which was never touched). Adjustment: the agent now re-verifies `git branch --show-current` immediately before every commit.
- **Red-phase refinement**: the first red run crashed the whole test process instead of failing — unimplemented interpolation left >±121 deltas that tripped the encoder's `precondition`. The test helper now guards deltas with `#expect`/`#require` so the red phase reports clean expectation failures; a crash-red hides every other test's result in the run.
- **US-106 landmine found while fixing header goldens**: decoding `color_change.dst` shows Catty consumed a pending color-change flag on the *first interpolated jump* (record 9 = `00 00 C3`, the dup), while Catroid semantics land it on the *final plain stitch* — two records differ in flag placement for the same program. ADR-012 doesn't pin this case yet; it must be decided before US-106 can be byte-identical against that fixture (the header metadata is unaffected — ST/CO/extents agree either way).
- **Ripple into US-104 tests**: the header goldens' stand-in streams (zigzags with 500-unit moves) started interpolating and inflated ST. Fixed by building those streams from the fixtures' *actual* programs — a single interpolated 500-unit move now reproduces `stitch.dst`'s ST=8 for real, which is a net gain in fixture fidelity heading into US-106.

## 2026-07-09 — US-106 plan rejected for skipping the configured planning agent; standing rule added (Sebastian + Claude Code)

- **Task**: US-106 planning. The plan was researched with generic exploration agents and presented without running the installed swift-engineering plugin's `swift-architect` agent, despite CLAUDE.md saying to consult the plugin's agents for planning/review.
- **Outcome**: Sebastian rejected the plan at the approval prompt ("did you make sure to use the configured agents?") and made it a standing rule. The `swift-architect` run was done before re-presenting; its design was adopted (a `DSTFile` value struct mirroring the `DSTHeader`/`DSTStitchRecord` idiom instead of the draft's enum-with-statics, a pure testable byte-differ, and a follow-up refactor retargeting `InterpolationTests` onto the production generator) — a concrete quality delta over the draft, not just process compliance.
- **Adjustment**: CLAUDE.md "Agentic workflow rules" now mandates the plugin agents at their phases (`swift-architect` in planning, `swift-code-reviewer` before close-out); also stored as agent memory so future sessions apply it unprompted.

## 2026-07-09 — US-105 landmine resolved: color-change flag placement pinned as ADR-013 (Sebastian + Claude Code)

- **Task**: decide the flag-placement divergence found in US-105 (Catty fixture: `0xC3` on the first interpolation jump; Catroid and our stream: on the final plain stitch) before US-106's golden test could be written.
- **Outcome**: presented both options with byte-level consequences; Sebastian's criterion was neither reference per se but *the Catroweb workflow* — same shared program, same DST on both platforms — which selects Catroid placement. Pinned as ADR-013: stream code unchanged; the `color_change.dst` golden compares through a documented two-byte flag transposition; a freshly generated color-change file goes back through Ink/Stitch since the transposed bytes are no longer the viewer-verified original.
- **Adjustment**: none beyond the ADR; the plan-phase journal re-read is what surfaced the landmine before any test was written.

## 2026-07-09 — US-106 DST file generator: reviewer agent found a real boundary trap (Claude Code)

- **Task**: US-106 (`DSTFile` serializer + golden verification), red→green→refactor flow on PR #8; first story under the new mandatory-plugin-agents rule (`swift-architect` in planning, `swift-code-reviewer` before close-out).
- **Outcome**: worked. Red baseline 295ff3a (8 failing tests), green e1c9262 — both goldens matched on the first implementation attempt (`stitch.dst` byte-identical; `color_change.dst` via the ADR-013 transposition, generated file differing from the fixture in exactly the two predicted bytes, `cmp`-verified). The red CI run again doubled as the early lint gate (`optional_data_string_conversion` — SwiftLint prefers the failable `String(bytes:encoding:)`, the *opposite* of the assumed direction). One process slip repeated a known lesson: the first red run crashed (signal 5) because a test indexed short stub data — the exact "crash-red hides every other result" trap the US-105 journal records; fixed with `#require` before indexing.
- **Delegation win worth recording**: the `swift-code-reviewer` agent found a production-reachable latent crash the whole TDD suite missed — at an exact ±121-unit boundary the interpolation guard rounds the stage *difference* while the record delta subtracts *rounded positions*; stage `(-0.3,0) → (60.3,0)` skips interpolation but yields delta 122 and traps `DSTFile`'s precondition. It also established that Catroid shares the asymmetry and silently emits a corrupt record there (`CONVERSION_TABLE[122]` is the −1 entry), so byte-parity would mean parity-with-corruption. Tracked as an open follow-up needing an ADR decision (crash vs. corrupt vs. widened guard) before export ships to users; noted in PR #8.
- **Adjustment**: none new; the review-before-close-out rule paid for itself on its first outing.

## 2026-07-09 — US-106 viewer check: square gap traced to a moving color-change record (Sebastian + Claude Code)

- **Task**: manual Ink/Stitch verification of three generated US-106 files (required by ADR-013 and the milestone exit criterion).
- **Outcome**: pass. The jumps-only regenerations (`stitch`, `color_change`) rendered as nothing — expected, US-101 precedent. The sewn two-color square rendered and simulated correctly except one missing top-edge segment, which Sebastian flagged as a possible Inkscape error. pyembroidery decode showed it is real: the color-change flag sits on a *moving* stitch (one 2 mm step), and viewers assign that segment to neither color block. Both references only ever emit zero-delta color-change records; the moving variant arises from our deliberate mid-stream color-change divergence (ADR-012) interacting with flag-on-next-stitch semantics.
- **Adjustment**: design note carried into US-110 (thread color story): emit the color change on a zero-delta record at the current position before the next move, so no sewn segment is lost. US-106 unaffected — the serializer faithfully encodes the stream, byte-verified.

## 2026-07-09 — Agent roster mapped to workflow phases; delegation boundary written down (Sebastian + Claude Code)

- **Task**: Sebastian asked, before merging PR #8, whether more of the swift-engineering plugin's eleven agents should join the workflow (only `swift-architect` and `swift-code-reviewer` were mandated so far).
- **Outcome**: roster reviewed against US-106 evidence. Principle extracted: *delegation suits verification and retrieval; generation only against a complete spec* — the reviewer succeeded because review checks artifacts without needing conversation context, while generation depends on pinned semantics (ADR-012/013, journal lessons) subagents don't inherit. Added to the workflow: `swift-search` (default for code-location queries), `swift-documenter` (milestone close, package READMEs), `swift-ui-design`/`swiftui-specialist` (from M3). Explicitly excluded: `swift-test-creator` for story tests (its "after implementation" premise inverts TDD, and tests are the byte-semantics spec), `tca-*` (ADR-006), `swift-modernizer` (greenfield). `swift-engineer` gets a defined pilot shape — implement a green phase against already-red tests in M2 — with the outcome to be journaled as a delegation comparison.
- **Adjustment**: CLAUDE.md agent rule expanded with the per-phase roster and an explicit "delegation boundary" rule.

## 2026-07-09 — Codex cross-vendor review automated: /codex-review command + PR-creation hook (Sebastian + Claude Code)

- **Task**: Sebastian asked whether Codex should use the swift-engineering subagents. Assessment: it can't (they're Claude Code plugin definitions with Skill/tool references Codex can't resolve), and it shouldn't inherit the same rubric — Codex's value in the tool split is *independence*, and US-106's boundary-trap find showed diversity of attention beats duplicated checklists. Sebastian's follow-up requirement: the Codex review must be invoked automatically by the workflow, not remembered manually.
- **Implementation**: (1) `.claude/commands/codex-review.md` — runs `codex exec review --base main -s read-only` with an adversarial-semantics rubric (attack the DST bytes against ADR-012/013; explicitly no style/architecture comments, the plugin reviewer owns those), then triage-with-ADRs-as-arbiter and verdict recording in the PR; (2) the PostToolUse Bash hook gained a `gh pr create` branch injecting a run-/codex-review reminder at PR creation (pipe-tested all four payload shapes, live-fired via `gh pr create --help`); (3) `/finish` gained step 6 verifying the verdict is recorded before handover; (4) CLAUDE.md documents the rule. Codex CLI was installed on PATH for this (the Codex.app-bundled binary worked but was awkward to invoke).
- **Adjustment**: review is now two-layer by construction — in-loop `swift-code-reviewer` (same-family, full plugin skills) before close-out, cross-vendor Codex (different model, semantics-adversarial) at PR time, both hook/checklist-enforced. The intended dogfood on US-106 was overtaken by events (Sebastian merged PR #8 while the first invocation was still being debugged — `exec` flags must precede the `review` subcommand); first live run is on this automation's own PR instead, with US-107 as the first real story under the rule.

## 2026-07-10 — First live Codex review found 5 real automation bugs, including one Claude missed entirely (Codex + Claude Code)

- **Task**: first live run of `/codex-review`, dogfooded on its own PR (#9). Two invocation failures first: `codex exec review` rejects `-s` (exec options must precede the subcommand), then rejects a custom prompt combined with `--base` — final form is plain `codex exec -s read-only` with the diff scope (`git diff main...HEAD`) inside the prompt. Correction to the 2026-07-09 automation entry: it recorded the never-working `codex exec review --base main -s read-only` form (that entry stands as written — this journal is append-only, per Sebastian: editing entries kills the file's purpose as raw thesis data).
- **Outcome**: 5 findings, all triaged valid, all fixed. The standout: **AGENTS.md exists, claims to mirror CLAUDE.md, and was never synced** with any of this week's rule changes — Claude had missed the file's existence across every session; a cross-vendor reviewer reading the repo fresh caught it immediately. Also valid: the hook's if/elif chain let `git push && gh pr create` suppress the push→CI reminder (both reminders now emitted, built via `jq --arg`); env-prefixed `VAR=x gh pr create` escaped the matcher (regex hardened); `gh pr create --help` false-fired (guarded); plus the invocation record above. Fixes pipe-tested against ten payload shapes.
- **Adjustment**: AGENTS.md now carries the two-layer-review handover rule (agent-agnostic phrasing) and the ADR-001…013 range, and "sync AGENTS.md with CLAUDE.md changes" is recorded as part of the rule. Thesis data point: the cross-vendor reviewer's first outing justified the independence argument — its unique catch (AGENTS.md) is exactly the fresh-eyes class of finding the same-family in-loop reviewer structurally can't make, since the omission lived in the context it inherited.

## 2026-07-10 — Journal declared append-only (Sebastian + Claude Code)

- **New rule from Sebastian**: entries in this journal are never edited or amended — editing kills its purpose as the unrevised raw record for the thesis; corrections are new dated entries referencing the old one. Triggered when Claude tried to fix the 2026-07-09 automation entry's invalid `codex exec review` invocation in place.
- **Adjustment**: rule pinned in this file's header, CLAUDE.md ("Agentic workflow rules"), AGENTS.md (process rules), and agent memory.

## 2026-07-10 — US-107: green-phase delegate caught a defective test; Codex produced a verified float-divergence repro (Claude Code + swift-engineer + Codex)

- **Task**: US-107 running stitch pattern — first full story under the two-layer review rule and the swift-engineer green-phase pilot defined on 2026-07-09. AC amended with Sebastian's approval before implementation: patterns return `[StagePoint]`, not `[Stitch]` (the literal signature would have moved unit conversion and flag authority out of the stream, contradicting the AC's own single-writer rationale and ADR-012's stage-space interpolation).
- **Delegation outcomes**: (1) *swift-architect*: first launch died silently (zero tool calls, boilerplate return); an identical relaunch delivered a strong plan whose computed test coordinates all survived review — transient-failure data point. (2) *swift-engineer green phase* (algorithm spec + red tests + stop-don't-fix mandate): implemented both files, then **stopped and reported that one test assertion was wrong** — resume-without-drift called `update` twice at the same needle position; a zero-distance second call must emit nothing, as the suite's own `surplusDropped` test pins. The delegate enforced "never change tests to go green" against the test author; test corrected with rationale (1be6fa9). (3) *swift-code-reviewer*: verified port fidelity line-for-line; one blocking find — `Int(NaN)`/`1...0` traps on `length <= 0`, which is Catroid's own formula-error fallback value. Trap reproduced red, then guarded as a documented deliberate divergence (Java NaN-poisons its anchor and goes permanently dead; we emit nothing and stay alive). (4) *Codex cross-vendor* (PR #10): 3 findings, zero code changes, all triaged with ADR-012 as arbiter — verdict in the PR. Standout: a concrete float32-vs-Double repro (length 1, (−10,−10)→(−148,81): interpolated stitch 98 lands at (−93,44) in Double where Catroid's float gives (−93,45)) — **verified real** by mimicking Java float arithmetic in Swift. ADR-012 pins stream/DST semantics, not pattern-layer arithmetic width, and `Double` is deliberate (engine-native, matches Catty prior art), so no fix — but the acceptance of last-ulp divergences from Android output is an open decision to pin in an ADR.
- **Adjustment**: none new to the workflow — both review layers and the delegation boundary performed as designed. Carried forward: ADR candidate for pattern-layer `Double` arithmetic (with the degenerate-length guard divergence folded in), and the Codex-named test blind spot that no test yet pipes pattern output through `EmbroideryStream`/`DSTFile` to bytes (lands naturally with the M2 virtual-needle wiring).

## 2026-07-13 — /finish's story-checkbox step was skipped for US-107 before merge (Sebastian + Claude Code)

- **Task**: Sebastian asked whether US-107 was done. It was — PR #10 merged, 74/74 tests green, journal entry and Codex verdict both already recorded — but `docs/user-stories/milestone-1/US-107-running-stitch-pattern.md` still had every AC checkbox unchecked and no `Status:` line, unlike US-101 through US-106, which were all flipped at close-out. The gap: the session ended (merge) right after the journal-entry commit, without a final `/finish` pass over the story file itself.
- **Outcome**: ran `/finish` retroactively — verified all 5 ACs against the merged code (`StitchPattern`/`NeedleUpdate`/`RunningStitch`/`RunningStitchPattern`), ticked the checkboxes, added the `Status: Done` line. No new DECISIONS/ROADMAP change (the Double-arithmetic ADR candidate stays parked, per [[project-parked-codex-plan-review]]).
- **Adjustment**: none to the process itself — `/finish` already covers this step; the miss was not invoking it as the literal last action before merging. Worth a habit check on future stories: run `/finish` *after* the journal-entry commit but *before* merging the PR, not just before creating it.

## 2026-07-13 — US-108 zigzag: both review layers landed blocking finds; ADR-014 recorded and corrected same-day (Claude Code)

- **Task**: US-108 `ZigzagStitchPattern` — swift-architect plan, main-agent red tests (Catroid golden rows + heading semantics), swift-engineer green phase, swift-code-reviewer, PR #12, `/codex-review`.
- **Delegation outcomes**: (1) *swift-architect*: first launch died silently again (zero tool calls, boilerplate return — second occurrence of the US-107 transient; relaunch-once is now a proven recovery); the retry independently re-derived all five Catroid golden rows and contributed two things the main-agent spec lacked: the `count == 0` loop-trap edge on the exclusive midpoint loop, and the compiling-stub-in-the-[red]-commit tactic so CI's red baseline is failing assertions rather than a build break. (2) *swift-engineer green phase* (red tests + stop-don't-fix mandate): clean one-shot — hand-verified the trickier expected values against the algorithm before implementing, changed no tests. (3) *swift-code-reviewer*: port fidelity verified line-for-line with zero findings, but one **blocking** find outside the port itself — `Int(ratio)` traps on guard-passing inputs (needle 1e19, length 1), and the same expression was already merged in US-107's `RunningStitchPattern`; both fixed behind `maxStitchesPerUpdate` (1e6, ADR-014) after a crashing red repro. Java saturates its `(int)` cast and hangs instead — neither accident ported. (4) *Codex cross-vendor* (PR #12): 3 findings, verdict "changes requested" — one real code bug the in-loop review had only gestured at as an advisory (finite `heading = .greatestFiniteMagnitude` overflows `(heading+90)·π` → NaN points → downstream trap; fixed by mod-360 normalization, red test first), and two corrections to ADR-014's *text*: the byte-parity consequence overclaimed (float-vs-Double can flip threshold crossings and javaRound boundaries — divergence acknowledged and accepted, not denied), and the negative-length rationale misattributed NaN-poisoning to Catroid (only length 0 poisons; negatives emit duplicate spam — verified against the Java).
- **ADR-014 unparked**: the pattern-layer Double-arithmetic candidate parked 2026-07-10 was recorded this story (Sebastian approved during planning) and then sharpened twice by Codex within hours of being written. New data point for the thesis: the cross-vendor reviewer attacked the *decision record itself*, not just the code — an ADR-review role neither layer was explicitly asked to play.
- **Carried forward**: pattern→stream→bytes differential test blind spot (unchanged from US-107, lands with M2 virtual-needle wiring); engine-wide coordinate-domain question (finite-but-huge emitted coordinates still trap at `EmbroideryPoint` conversion — swift-code-reviewer advisory, backlog).

## 2026-07-13 — US-108 second Codex round (Sebastian-requested re-review of the fixes) (Sebastian + Claude Code)

- **Task**: Sebastian asked for a Codex re-review of PR #12 after the first round's fixes landed — first time a verification pass has been run on a triage outcome rather than on fresh code.
- **Outcome**: all three prior findings confirmed fixed, and 3 new findings: (1) *the fix itself reviewed* — mod-360 heading normalization diverges from Catroid for enormous finite headings; triaged as domain-unreachable (Catroid's sprite layer pre-normalizes to (−180, 180], so no reference semantics exist there) and pinned as a deliberate periodic extension in ADR-014 + a periodicity test, no code change. (2) Huge finite *width* reaches the downstream `Int` trap — a concrete reproducer for the already-tracked engine-wide coordinate-domain backlog item; stays out of scope (positions cause the same trap in merged US-107 code; needs one chokepoint fix at stream ingestion, likely its own ADR/story). (3) Stale doc comments contradicting the corrected ADR-014 (zigzag type header, `maxStitchesPerUpdate` off-by-anchor wording) — fixed.
- **Thesis note**: the re-review earned its cost: it audited the *remediation* (finding 1 targeted the very line added to satisfy round 1) and downgraded severity overall (High→none, verdict effectively accept-with-notes vs "changes requested"). Diminishing but non-zero returns; a third round was not run.

## 2026-07-13 — New workflow rule: Codex verification round after finding-driven fixes (Sebastian + Claude Code)

- **Task**: Sebastian, after the US-108 re-review: "adapt the workflow to also run the codex check again if something was found the first round, just like we did now."
- **Change**: `/codex-review` gains step 5 — whenever a round's triage changed the branch (code or docs), Codex re-reviews with a verify-then-hunt prompt: each prior finding is listed with its claimed fix and checked for correctness *and* for divergence introduced by the fix itself, then a fresh adversarial pass over the current diff. Loop while rounds produce **code** changes; all-rejected or doc-only rounds end it; hard cap 3 rounds, then escalate to Sebastian. CLAUDE.md and AGENTS.md rule 4 updated in sync; handover now requires the *final* round's verdict recorded.
- **Rationale (thesis data)**: US-108's manual round 2 caught a Catroid divergence in the exact line added to satisfy round 1 — remediation is itself unreviewed code, and the first-round reviewer is the natural auditor of it. The observed severity trend (High → no code bugs) sets the stop condition; the cap guards against a review/fix ping-pong.
