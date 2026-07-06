# US-101 — Project scaffold, SPM package and CI

**Epic**: E1 Infrastructure | **Estimate**: ~4 h | **Depends on**: —

**Story**: As a developer, I want a scaffolded repository with a Swift package, linting and CI, so that every subsequent story starts from `swift test` running green on every push.

## Acceptance criteria
- [ ] Swift package `EmbroideryEngine` exists under `Packages/EmbroideryEngine` (library target + test target, Swift 6 language mode with **strict concurrency enabled**, platforms: iOS 17 / macOS 14 so tests run on CI without a simulator).
- [ ] Test target uses **Swift Testing** (`import Testing`, `@Test`/`#expect`) — not XCTest. A trivial placeholder test passes locally via `swift test` run inside the package directory.
- [ ] SwiftLint configured (`.swiftlint.yml`) and passing — current SwiftLint defaults plus Catrobat's non-style rules (Catty's config predates Swift 6/SwiftUI; don't copy it).
- [ ] GitHub Actions workflow runs `swift test` + SwiftLint on push and pull request, with the **Xcode/Swift toolchain version pinned** (runner-default drift breaks Swift 6.x builds); badge in README.
- [ ] Reference fixtures (`stitch.dst`, `color_change.dst` from Catty's test resources) copied into the repo with provenance notes and **verified to render correctly in a named embroidery viewer** (~15 min) — they are Catty-generated "self-golden" files, so trust must be established before US-104/US-106 build golden tests on them.
- [ ] `LICENSE` = AGPL-3.0 (Catrobat standard), README describes the project in 2–3 paragraphs (what, why, thesis context, upstream Catrobat links).
- [ ] Repo-level `CLAUDE.md` records build/test commands.

## Test-first plan
1. Write the placeholder Swift Testing test (`@Test func packageBuilds() { #expect(true) }`, replaced immediately in US-102) — the point of this story is the *pipeline*: a failing lint or test must fail CI. Verify by pushing a deliberately failing commit on a branch, then fixing it.

## References
- `Paintroid-Flutter/` repo hygiene (CI layout, contribution docs) as structural template.
- `Catty/.swiftlint.yml` for lint baseline.
