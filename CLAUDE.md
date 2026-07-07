# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A standalone native iOS app bringing Catrobat's embroidery functionality (the Android "Embroidery Designer" flavor) to iOS: users program embroidery designs with Pocket Code-style visual blocks, watch the live stitch preview, and export machine-readable Tajima DST files. Developed as a bachelor-thesis open-source contribution; to be transferred to the Catrobat organization after sign-off. License: AGPL-3.0.

**Read before working**: `docs/ROADMAP.md` (epics, milestones, engineering standards), `docs/DECISIONS.md` (ADR-001…012 — ADR-012 pins the byte-level DST semantics and lists known reference bugs never to port), and the current milestone's stories in `docs/user-stories/`.

## Non-negotiable process rules

1. **Test-driven development**: write the failing tests first (they're listed per story under "Test-first plan"), then implement. No implementation-first code.
2. **Small iterations**: one user story (≤ ~5 h) at a time; many small, coherent, buildable commits.
3. Where the Catroid and Catty references disagree, **ADR-012 is the arbiter** — never "fix" a red golden test by consulting the other reference.

## Stack & standards

- Swift 6 (strict concurrency), SwiftUI, min iOS 17, universal (iPhone-first). App layer: `@Observable` MVVM on `@MainActor`, no architecture frameworks (ADR-006).
- Engine lives in `Packages/EmbroideryEngine` — platform-independent, synchronous, `Sendable` value types, no I/O; test with `swift test` run inside the package directory (no simulator needed).
- **Swift Testing only** (`@Test`/`#expect`/`#require`), never XCTest. Tests run in parallel: no shared mutable state or fixed file paths; fixtures via `Bundle.module`.
- The `swift-engineering` Claude Code plugin is installed — consult its skills when writing Swift (`swift-testing`, `modern-swift`, `swift-style`, `swiftui-patterns`, `ios-hig`, `localization`, `swift-diagnostics`) and its agents for planning/review. The Sosumi MCP server provides live Apple docs.

## Build & test

- Engine (once `Packages/EmbroideryEngine` exists): `cd Packages/EmbroideryEngine && swift test` — fast, no simulator.
- App: `xcodebuild -project catrobat_embroidery_ios/catrobat_embroidery_ios.xcodeproj -scheme catrobat_embroidery_ios -destination 'platform=iOS Simulator,name=iPhone 17' test` (or `build`).
- Prefer the XcodeBuildMCP tools (`build_sim`, `test_sim`, simulator/screenshot tools) over raw `xcodebuild` — they return structured errors and per-test results.

## Agentic workflow rules

- **Prove red before green**: after writing a story's tests, run them and show the failures before writing any implementation. A test never seen failing proves nothing.
- **Never commit red**: a PreToolUse hook in `.claude/settings.json` runs the engine tests before any `git commit` and blocks if they fail. Red is fine while working, never in a commit.
- **Never edit `*.pbxproj`** (permission rule asks first): app sources use synchronized folder groups, so Swift files created on disk under `catrobat_embroidery_ios/catrobat_embroidery_ios/` are picked up automatically. Target/package-dependency changes are done by the human in Xcode.
- Edited Swift files are auto-formatted by a PostToolUse SwiftFormat hook (no-ops if `swiftformat` is missing).
- **UI stories**: definition of done includes building, running on the simulator, and capturing a screenshot via XcodeBuildMCP for visual review.
- After notable workflow events (delegation wins/failures, new hooks or rules, tool comparisons), append a short entry to `docs/workflow-journal.md` — it is thesis data.

## Reference repositories

The sibling checkouts (one level up, read-only; access granted via `.claude/settings.local.json`):
- `../Catroid` — canonical embroidery implementation: `catroid/src/main/java/org/catrobat/catroid/embroidery/`
- `../Catty` — Swift prior art: `src/Catty/Embroidery/`; golden fixtures in `src/CattyTests/Resources/EmbroideryReference/`
- `../Paintroid-Flutter` — Catrobat's newest repo; template for repo hygiene/conventions only

Port concepts, not wholesale code; everything is AGPL-3.0 (note provenance where data like the DST conversion table is ported verbatim).
