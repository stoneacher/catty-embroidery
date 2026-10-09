# AGENTS.md

This file provides guidance to AI coding agents (Codex and others) working with code in this repository. It mirrors `CLAUDE.md`; keep the two in sync.

## What this is

A standalone native iOS app bringing Catrobat's embroidery functionality (the Android "Embroidery Designer" flavor) to iOS: users program embroidery designs with Pocket Code-style visual blocks, watch the live stitch preview, and export machine-readable Tajima DST files. Developed as a bachelor-thesis open-source contribution; to be transferred to the Catrobat organization after sign-off. License: AGPL-3.0.

**Read before working**: `docs/ROADMAP.md` (epics, milestones, engineering standards), `docs/DECISIONS.md` (**start with its index**: one line per ADR with its current rule and status; ADR-012 pins the byte-level DST semantics and lists known reference bugs never to port, and the DST contract lives in 012/013/015/020/025; superseded ADRs stay as the record and name their successor), and the current feature's brief in `docs/features/` (ADR-041: work is organised by feature, not by ≤ 5 h story; `docs/user-stories/` is the history of M1–M4).

## Non-negotiable process rules

1. **Test-driven development**: write the failing tests first (the feature brief's test-first outline names them), run them, and show the failures before implementing. No implementation-first code. Red → green happens per slice inside the feature, not once for the whole feature.
2. **Feature-sized units of work** (ADR-041): one feature (e.g. the brick backend, the editor UI, variables) per branch and PR, built out in as many slices as it naturally has. No hour estimates. Commits stay coherent and buildable, but their size follows the work rather than a story budget. **The PR has a size limit even though the feature has no time limit**: when a feature's diff passes roughly 1,500 lines of non-test code, split it into several PRs (e.g. engine, then app). Every slice is mutation-checked (ADR-032 invariant 2): a plausible mutation of the code under test must turn its tests red, and the result is recorded. Never commit with failing engine tests, except a deliberate `[red]` commit.
3. Where the Catroid and Catty references disagree, **ADR-012 is the arbiter** — never "fix" a red golden test by consulting the other reference. The same authority rule covers *generated* artifacts: a knowledge graph, index or summary of the docs never overrides an ADR. Where the two disagree, the ADR is right and the derived artifact is stale or wrong.
4. **Two-layer review before handover**: every PR gets an in-loop code review during the session plus an independent cross-vendor review — and a **risky slice** (DST bytes, engine, interpreter, program format) gets both reviews (one cross-vendor round) as soon as the slice is done, not only at handover. A feature whose semantics are not already pinned has its brief reviewed cross-vendor before tests are written. The cross-vendor rubric is in `.claude/commands/codex-review.md`; the handover verdict recorded in the PR description before the PR is handed over for merge. If review findings changed the branch, a verification round re-reviews the fixes. **The loop ends when a round produces no code changes, or when severity has fallen for two consecutive rounds; hard cap 5 rounds** (ADR-041), at which the loop stops and any valid findings still open are fixed without a further round or tracked in the PR. Each round's highest severity is recorded, because the stop condition depends on that history; the final round's verdict must be recorded. PRs created outside Claude Code must satisfy the same rule.
5. **`docs/workflow-journal.md` is append-only** (thesis data) and stays exhaustive: never edit an existing entry; corrections are new dated entries referencing the old one. Entry granularity follows the circumstance — one per feature for a quiet feature, one per notable event otherwise — and every entry should make sense on its own.
6. **The close of a major feature runs a knowledge-graph drift check** (when the feature added or changed ADRs) — `/graphify . --update` in Claude Code — never per slice. Its purpose is to surface where new work has restated an invariant an existing ADR already owns. **The step is defined by its output, not by its effort**: it is satisfied only when a graph has been built over the whole corpus and the `semantically_similar_to` edges crossing the `docs/` communities have been triaged one by one. Reading the corpus and concluding "nothing found" does not satisfy it; if the tool is unavailable in your harness, record that in the journal and leave the step undone rather than substituting a file read. The outcome — including "none, N edges triaged" — goes in the journal. It runs alongside the `swift-documenter` pass (package READMEs for stabilised public API), which is a Claude Code step and is not required of other agents. `graphify-out/` is derived: only `GRAPH_REPORT.md` is tracked; the graph data, HTML viewer and cache are ignored. Rule 3 governs anything the graph claims.
7. **Open a draft PR right after a feature branch's first commit** (a PR needs at least one commit beyond `main`). CI runs `push` on `main` only (ADR-023, 2026-09-28 amendment), so a branch without a PR gets no CI; opening the PR runs CI on the commits already there, so a `[red]` first commit still shows its red baseline. Mark it ready for review at handover, which is when the cross-vendor review runs.

## Stack & standards

- Swift 6 (strict concurrency), SwiftUI, min iOS 17, universal (iPhone-first). App layer: `@Observable` MVVM on `@MainActor`, no architecture frameworks (ADR-006).
- Engine lives in `Packages/EmbroideryEngine` — platform-independent, synchronous, `Sendable` value types, no I/O; test with `swift test` run inside the package directory (no simulator needed).
- **Swift Testing only** (`@Test`/`#expect`/`#require`), never XCTest. Tests run in parallel: no shared mutable state or fixed file paths; fixtures via `Bundle.module`.
- Format Swift with SwiftFormat using the repo's `.swiftformat` config.

## Build & test

- Engine (once `Packages/EmbroideryEngine` exists): `cd Packages/EmbroideryEngine && swift test` — fast, no simulator.
- App: `xcodebuild -project catrobat_embroidery_ios/catrobat_embroidery_ios.xcodeproj -scheme catrobat_embroidery_ios -destination 'platform=iOS Simulator,name=iPhone 17' test` (or `build`).
- **Never edit `*.pbxproj`**: app sources use synchronized folder groups, so Swift files created on disk under `catrobat_embroidery_ios/catrobat_embroidery_ios/` are picked up automatically. Target/package-dependency changes are done by the human in Xcode.

## Reference repositories

The sibling checkouts (one level up) are **read-only references — never modify them**:
- `../Catroid` — canonical embroidery implementation: `catroid/src/main/java/org/catrobat/catroid/embroidery/`
- `../Catty` — Swift prior art: `src/Catty/Embroidery/`; golden fixtures in `src/CattyTests/Resources/EmbroideryReference/`
- `../Paintroid-Flutter` — Catrobat's newest repo; template for repo hygiene/conventions only

Port concepts, not wholesale code; everything is AGPL-3.0 (note provenance where data like the DST conversion table is ported verbatim).
