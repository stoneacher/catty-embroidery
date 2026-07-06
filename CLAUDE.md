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

No Xcode project yet (arrives in M3). Once targets exist, record the canonical commands here:
- Engine: `cd Packages/EmbroideryEngine && swift test`
- App (expected shape): `xcodebuild -scheme <Scheme> -destination 'platform=iOS Simulator,name=iPhone 17' test`

## Reference repositories

The sibling checkouts (one level up, read-only; access granted via `.claude/settings.local.json`):
- `../Catroid` — canonical embroidery implementation: `catroid/src/main/java/org/catrobat/catroid/embroidery/`
- `../Catty` — Swift prior art: `src/Catty/Embroidery/`; golden fixtures in `src/CattyTests/Resources/EmbroideryReference/`
- `../Paintroid-Flutter` — Catrobat's newest repo; template for repo hygiene/conventions only

Port concepts, not wholesale code; everything is AGPL-3.0 (note provenance where data like the DST conversion table is ported verbatim).
