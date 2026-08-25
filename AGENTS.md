# AGENTS.md

This file provides guidance to AI coding agents (Codex and others) working with code in this repository. It mirrors `CLAUDE.md`; keep the two in sync.

## What this is

A standalone native iOS app bringing Catrobat's embroidery functionality (the Android "Embroidery Designer" flavor) to iOS: users program embroidery designs with Pocket Code-style visual blocks, watch the live stitch preview, and export machine-readable Tajima DST files. Developed as a bachelor-thesis open-source contribution; to be transferred to the Catrobat organization after sign-off. License: AGPL-3.0.

**Read before working**: `docs/ROADMAP.md` (epics, milestones, engineering standards), `docs/DECISIONS.md` (ADR-001…028, numbering skips 025/026 — ADR-012 pins the byte-level DST semantics and lists known reference bugs never to port; ADR-013 pins color-change flag placement; ADR-015 pins thread-color emission semantics; ADR-016 pins the M2 ProgramModel/Interpreter target split; ADR-017 pins formula-arithmetic divergences; ADR-018 pins interpreter tick/clock semantics; ADR-019 pins how a golden sitting on a threshold must guard itself; ADR-020 pins the engine's coordinate boundary; ADR-021 pins the M3 preview data path; ADR-022 pins the M3 target layout; ADR-023 pins what runs where — the local commit gate compiles the app, CI runs it; ADR-024 pins the stage renderer; ADR-027 pins the run lifecycle — two tasks with producer-only cancellation, a terminal that cannot omit the export model, and three budget axes; ADR-028 pins zoom/pan and the stage's VoiceOver summary — one commit per gesture, a fit-aware zoom floor, and a summary only a run-state transition may write — ADR-025 is reserved for US-211 and ADR-026 for US-308), and the current milestone's stories in `docs/user-stories/`.

## Non-negotiable process rules

1. **Test-driven development**: write the failing tests first (they're listed per story under "Test-first plan"), run them, and show the failures before implementing. No implementation-first code.
2. **Small iterations**: one user story (≤ ~5 h) at a time; many small, coherent, buildable commits. Never commit with failing engine tests.
3. Where the Catroid and Catty references disagree, **ADR-012 is the arbiter** — never "fix" a red golden test by consulting the other reference. The same authority rule covers *generated* artifacts: a knowledge graph, index or summary of the docs never overrides an ADR. Where the two disagree, the ADR is right and the derived artifact is stale or wrong.
4. **Two-layer review before handover**: every PR gets an in-loop code review during the session plus an independent cross-vendor review (rubric in `.claude/commands/codex-review.md`), with the verdict recorded in the PR description before it is handed over for merge. If review findings changed the branch, a verification round re-reviews the fixes. **The loop ends when a round produces no code changes, or when severity has fallen for two consecutive rounds — not on a fixed count**; a flat severity run is not convergence. Hard cap 10, escalating early if severity stays flat or rises for three rounds. Each round's highest severity is recorded, because the stop condition depends on that history; the final round's verdict must be recorded. PRs created outside Claude Code must satisfy the same rule.
5. **`docs/workflow-journal.md` is append-only** (thesis data): never edit an existing entry; corrections are new dated entries referencing the old one.
6. **Milestone close runs a knowledge-graph drift check** (`/graphify . --update` in Claude Code, or any equivalent that reads the whole corpus), never per story. Its purpose is to surface where a new story has restated an invariant an existing ADR already owns; the findings — including "none" — go in the journal. `graphify-out/` is derived: only `GRAPH_REPORT.md` is tracked; the graph data, HTML viewer and cache are ignored. Rule 3 governs anything it claims.

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
