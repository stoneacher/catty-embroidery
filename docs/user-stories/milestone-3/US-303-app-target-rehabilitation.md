# US-303 — App target rehabilitation, navigation skeleton, app CI job

**Epic**: E1 Infrastructure | **Estimate**: ~4 h | **Depends on**: US-301, US-302

**Status**: Not started

**Story**: As a developer, I want the app target to actually be a Swift 6 iOS 17 app that links the engine and is verified by CI, so every later UI story starts from something that builds.

The app target is still the Xcode template: it links **none** of the package products, and as scaffolded it contradicts three ADRs. Nothing builds or tests it — the PreToolUse commit gate and `ci.yml` both run only `swift test` on the engine package, so the entire app layer is currently ungated. This story fixes both halves.

Its position after US-301/US-302 is forced, not narrative: the human Xcode session links package *products*, so `Samples` and `StagePreview` must exist first or the session has to be repeated.

**Prerequisite — human Xcode steps.** `*.pbxproj` is human-only (CLAUDE.md). The full ordered list is in the [milestone README](README.md#human-xcode-hand-off-prerequisite-for-us-303): link five products, deployment target 26.5 → 17.0, Swift 5.0 → 6.0, real bundle id, create `Info.plist` + `INFOPLIST_FILE`, add `Localizable.xcstrings`, share the scheme, delete the UITests target, delete the template `ContentView.swift`. This story does not start until they are done.

## Acceptance criteria
- [ ] `RootView` is size-class adaptive per ADR-010: compact → sequential (`NavigationStack`); regular → side-by-side (`NavigationSplitView`) with the stage on the detail side. Skeleton fidelity, no editor.
- [ ] `Localizable.xcstrings` exists and **every** user-facing string in this story goes through it with a translator comment. Layout uses leading/trailing throughout (Catrobat ships ~75 languages including RTL).
- [ ] The app imports and *uses* `Samples` and `StagePreview` in real code — not a dead import — so the link is genuinely exercised.
- [ ] A CI job `app-build-and-test` on `macos-26` with the same pinned `DEVELOPER_DIR` as the engine job, added to the required checks. **Every `xcodebuild` invocation passes `-project catrobat_embroidery_ios/catrobat_embroidery_ios.xcodeproj` explicitly** (or sets an equivalent working directory): the project is nested, GitHub Actions starts at the repository root, and a bare `xcodebuild -scheme …` finds nothing and fails before reaching a test. CLAUDE.md's own documented command already spells the path out — match it. (Codex round 1: the first draft of this story wrote bare commands.)
- [ ] The job depends on the shared scheme existing — `xcshareddata/xcschemes/` is absent today and a fresh CI checkout cannot be relied on to autocreate it.
- [ ] The local PreToolUse commit gate **keeps `swift test` engine-only** and gains a signing-free app *compile* check — `xcodebuild build -project catrobat_embroidery_ios/catrobat_embroidery_ios.xcodeproj -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` with a persistent `-derivedDataPath` outside the repo — conditioned on the staged diff touching `catrobat_embroidery_ios/`. Measured at 9.3 s cold on the pre-link target; **re-measure with five products linked and drop the check if it exceeds ~30 s incremental.** A simulator boot in a pre-commit hook is explicitly rejected: it would cost the small-commit cadence the whole process rests on.
- [ ] SwiftLint (already repo-root, so it starts seeing app sources the moment they appear) passes. Expect a first-time wave from the scaffolded files; clearing it belongs to this story.
- [ ] The tick/clock coupling is recorded: the app's clock is `InterpreterClock(tickDelta: 1.0/60.0)`, so at one tick per frame a `wait` brick tracks wall time (ADR-018 requires only `tickDelta > 0`).
- [ ] **Story-specific definition of done**: `RootView`'s split behaviour screenshotted at both size classes; navigation titles and the sample-list header localised; Dynamic Type to AX1 reflows the skeleton without truncation.
- [ ] Close-out pins **ADR-023**: what runs where, and why the local gate protects byte-level engine semantics while the app target's protection is CI's job.

## Test-first plan
1. App-target test: `SampleLibrary.all` is non-empty and every sample's display name resolves through the String Catalog with no literal fallback.
2. App-target test: constructing an `Interpreter` from a sample succeeds — the smoke test proving the products are genuinely linked, not just declared.
3. A no-hardcoded-strings check over this story's views. State the mechanism chosen (a grep-level check is acceptable at this fidelity) rather than leaving it implicit.
4. CI: push the branch and confirm the new job runs the app tests **and fails on a deliberately broken app-target compile** — prove the gate red before trusting it.
5. Local hook: confirm it blocks an app-target compile error and does **not** fire for an engine-only commit.

## References
- ADR-004 (min iOS 17 — the deployment target currently says 26.5), ADR-006 (`@Observable` MVVM on `@MainActor`; the scaffold's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is already this shape), ADR-010 (size-class adaptive from the start)
- `.claude/settings.json` — the PreToolUse engine test gate this story extends
- `.github/workflows/ci.yml` — currently engine tests + SwiftLint only
- ADR-023 (this story's close-out)
