# Milestone 3 — Walking skeleton app

**Status**: In progress — planned 2026-08-04. Ten stories (US-301…US-309 plus US-211, carried in from the backlog), ~40 h, **plus US-310**, added 2026-09-03 because US-309's measurement left the milestone's own exit criterion unmet on one path and named the work that fixes it (ADR-029 rung 2). **US-301 done 2026-08-09** (implemented 2026-08-07, Ink/Stitch verified 2026-08-09). **US-302 done 2026-08-11** (implemented and reviewed 2026-08-09, merged as PR #32; eight Codex rounds — 21 findings, all valid, final round clean — then an in-loop `swift-code-reviewer` pass that found two disjoint allocation defects). The package now has five library products and 489 engine tests. **US-303 done 2026-08-11**: the human Xcode hand-off below ran that day — all nine items, guided step by step and verified against `project.pbxproj` after each — and the app target now links the five products, builds as Swift 6 / iOS 17, and is gated by a new `app-build-and-test` CI job proven red before it was trusted. 6 app tests. Close-out pinned ADR-023, whose review loop ran to **nine Codex rounds** before closing clean. **US-304 done 2026-08-12**: the picker, plus the ADR-023 selection hoist it inherited without being asked. Rows are `Button`s rather than `List(selection:)`, because the latter cannot guarantee the re-selection event the story's own criterion requires — the obvious implementation would have been green and wrong. 14 app tests. **US-305 done 2026-08-13**: ADR-009 is code. The batching is a `StitchDrawPlan` value in `StagePreview` rather than logic in the renderer — forced, not chosen, because four of the story's nine test items asked to be asserted through a recording double's "path list" and a double conforming to `StagePreviewRenderer` records that protocol's *inputs*, so it never has one. Two criteria had contradicted each other three items apart, through three prior Codex rounds. 546 engine tests (up from 489) plus the app suite; four screenshots. The Codex loop ran four rounds (High → High → none → none) and **round 2 refuted my own triage of round 1**, which had deferred a real cropping defect by confusing a design's span with its per-direction DST extent. **US-306 done 2026-08-17** (PR #37): the preview is a live run. `InterpreterDriver` steps the interpreter off the main actor and yields one `RunUpdate` per frame through an unbounded `AsyncStream`; `PreviewRunState` folds each update in one mutation; the needle is a sibling `Canvas` layer so it can never enter the raster's bake key. Both things it inherited by name are discharged — `AppModel.drainSelectionForPreview` is deleted (and `AppModel` no longer imports the engine, the interpreter or the preview at all), and the watermark now advances in chunks of 1 000, which makes US-305's cached-raster path reachable at runtime for the first time and **answers ADR-024's open question**: `Image(size:renderer:)` rasterises at the display scale, so there is no seam at the watermark. **581 engine tests**, up from 546, plus 48 app tests and five screenshots. ADR-027 pins the lifecycle. In-loop review round 1 found a **Critical** the story's own reasoning had hidden: I had asserted that `AsyncStream.Iterator.next()` returns `nil` in a cancelled task, which is false while elements are buffered, and that false premise is why nothing guarded against a discarded run's buffered frames landing in the run that replaced it — measured, and reachable by picking a new sample mid-run. Two of the story's own criteria were wrong and one would have failed silently — "the run `Task`" is singular where there are necessarily two, and cancelling the *consumer* (the natural reading) drops the terminal update carrying `assembledStream()`, reproducing precisely the Catty hazard the criterion exists to close. Both halves of test item 5 were also vacuous as written, since the per-frame stitch budget is unreachable at the default `ticksPerFrame = 1`. **US-307 implemented 2026-08-18**: the stage is inspectable. Pinch and pan are composed simultaneously but committed **once**, in `onEnded` — SwiftUI's gesture values are cumulative from the gesture's start, so folding each callback in as a delta compounds them, and committing once also means the transform cannot change mid-gesture, which is what makes ADR-009's "re-rasterise on gesture end" **structural rather than timed**: `BakeKey` reads that transform. The canvas is one accessibility element whose value is rebuilt on run-state transitions only (2 against 139 batches for sample 1), enforced by hoisting state and summary into a separate `RunPhase` type — `private(set)` *inside* `PreviewRunState` would still have let `apply(_:)` write the summary every frame, because `private` means "within this type". **Done 2026-08-19** (PR #39), with the manual pass confirmed the same day. **649 engine tests** (up from 581), 65 app tests (up from 48), seven screenshots. ADR-028 pins it, with three corrections — the mid-gesture design reversed after two user-found defects, and the interaction layer rewritten after six rounds found one conceptual mistake in four spellings. **Six of the story's own criteria and test items could not be built as written**, all found at planning against the named source: test items 1 and 2a were **already green from US-302** (re-writing them yields tests that were never red), item 2b is **vacuous** under `nil`-means-fit, item 3's sentence is **unassertable** because `%lld` carries the reader's grouping separator, criterion 4 is **untestable and already true**, and **criteria 5 and 6 contradict each other** — a summary rebuilt only on transitions is computed when the display list is empty, so it would read "0 stitches" for the entire run. Numbers now appear only when final. A test of mine also asserted a locale and the simulator refuted it: the value renders as "3.194 stitches, 1 colour, 98,6 millimetres by 98,6 millimetres" — English words, German number formatting, because language and region are set separately. **Outstanding**: the VoiceOver pass, a real pinch and the two-zoom-level screenshots are not automatable here (single-finger tooling only; `simctl ui` exposes no VoiceOver and no Reduce Motion). **US-211 done 2026-08-25**: the header's field widths stop being a `precondition` on ordinary input — `DSTHeader.init` and `DSTFile.init` throw `DSTSerializationError.fieldOverflow(field:value:limit:)`, so the export path US-308 builds can say *which* limit was hit instead of the process dying. ADR-025 pins it, and pins two things the story had not seen: **field emission order is a contract** (a throwing `ST` check is what keeps the header's unguarded `Int` extent subtractions unreachable, and the extents being checked first is what keeps `AX` safe — at `"-9999"`, exactly filling its 5-wide field), and ADR-020's 1 000 000 split cap **stays**, against ADR-020's own speculation that it might want to be 999 996. The ripple was **41 call sites across 15 files**, not the 33 measured at planning. ADR-020's last open item is closed. **662 engine tests**, up from 649; goldens byte-identical with no re-blessing. Two review layers, 16 findings, none rejected — none of them a defect in the shipped behaviour, all sixteen in the surrounding layer. The story's red mechanism is reusable: for a story that replaces a trap with a typed error, the exit test asserts **`.success`**, since `.failure` passes while the bug is present. **US-308 done 2026-08-29**: the milestone's end-to-end thread is complete — pick a design, watch it stitch, name it, and send a machine-readable `.dst` out through the share sheet. Verified in the running app rather than only in tests: the exported file carries `LA:SquareCoil`, `ST:2976`, `CO:2` and 9443 bytes = 512 + 2976 × 3 + 3, in a per-session temp directory. **The name is in the bytes**, which is the whole point — Catty's shipping app writes `LA` blank and only its unit tests ever pass a name, and neither reference declares a `.dst` type at all (measured: the simulator resolves `.dst` to a system-invented `dyn.` placeholder, so there is no originator identifier to reuse). ADR-026 pins the gate, the two name types, eager preparation, the temp-file policy and the UTType. **710 engine tests** (up from 662) and **130 app tests** (up from 65); six screenshots; **no human Xcode session needed**, which was not obvious before planning. Two criteria forced each other into one shape: `ShareLink` takes its item at construction and reports failure to the *system* share UI, and `Transferable.exported(as:)` is iOS 18.2+ against an iOS 17 target — so preparation is **eager**, and a US-211 overflow is therefore a **gate reason** rather than a failed share, or its localised message is unreachable. **Twenty planning corrections**, and two test items turned out **already green** — item 6a four times over from ADR-025, and item 5 discovered so only *after* being written, which produced the cheap check for the class: does the new test file reference any symbol the story adds? Because most reds were compile failures, the discriminating assertions were checked by **mutation** instead — eleven, each caught by exactly its own test. Integration also found what planning had not: `DesignName` accepts `/` (the `LA` field carries it untouched) while a file name cannot, so deriving one from the other needs a sanitising path, not the validating one. **US-309 done 2026-09-02** (headless half 2026-09-01, device capture 2026-09-02): ADR-009's rendering bet stops being a claim. Measured, the *settled* 50k frame — which the story assumed was the risk — is trivially cheap: `live(of:)` at 50 000 settled costs **0.0013 ms** and is **1.00×** its cost at 5 000, and the discriminating test is structural rather than timed (100 dots, ≤ 101 segments, at any settled count). The two real risks are elsewhere and the story names neither: the **mid-gesture full re-stroke** ADR-028 left behind (0.45 ms of planning at 50k, **350×** the settled frame, before a 50 000-segment `Path` and 50 000 ellipses) and a **Θ(n²/chunk) bake schedule** whose last bake plans the whole design on one frame near the end of every long run. **736 engine tests** (up from 710) and **183 app tests** (up from 130). ADR-029 pins the measurement, the fallback ladder and a **negative result**: the proportional settle chunk the Θ(n²/chunk) finding seems to call for measured *worse* (176 bakes against 50), and the bake-versus-tail *balance point* depends on GPU work no `swift test` can measure, so the constant is the device session's first knob rather than a guess. **Every red was a compile failure**, so the bounds are proved by three mutations — the quadratic `append` measures **255.08** against a bound of 64 and a theoretical 256 — and the **survivor** was the best result: a test that *restated* the settle rule instead of observing it passed the mutant, which is why the rule is now a public pure function. **CI refuted a bound on unmutated code** (9.62× on the runner against 3.71× locally, because per-element append cost leaves cache), forcing a 16× step with a k^1.5 bound. ADR-021 is **corrected in place**: its 0.64 ms figure is a Mac number presented with an unstated ~2.6× A15 extrapolation — 0.64/16.67 is 3.8 % of a frame, not the 10 % claimed. **The device measurement then answered the exit criterion "half no"**: on an iPhone 17 Pro, over drawn frames, animating to 50 000 **passes clause 1** (p99 16.670 ms; the "no frame > 33.3 ms" clause is **untested by this instrument** — ADR-029 amendment, 2026-09-18) and **mid-gesture fails at a median of 69.1 ms** — about 14 fps, on hardware generations above the A15 the criterion names, so the failure cannot be blamed on the device. ADR-009's bet holds where it was claimed and fails on the path ADR-028 created by removing the mid-gesture blit; ADR-029's fallback ladder is re-ordered to start at rung 2, since the gesture path never bakes. The settled capture is the story's best artefact: `drawn=0`, p99 under the bar, worst frame *worse* than the animating capture's — a flawless-looking 60 fps at 50 000 stitches with the renderer having run zero times, which is exactly the false positive five review rounds existed to prevent. **736 engine tests and 191 app tests.** Remaining items are non-blocking and carried to the milestone's final verification. **US-310 done 2026-09-14** (implemented 2026-09-03; device session completed 2026-09-14): the mid-gesture path stops re-stroking every stitch. A drawn segment is now an index *pair*, and while `canUseRaster` is false the planner joins thread intervals up to a stride and strides the dots per colour run — coarsening rather than ADR-029's literal "every k-th segment", which would have dashed the thread and saved nothing on the dots. Measured with the same instrument and protocol at 50 001 stitches mid-drag, the **median frame falls from 36.1 ms to 16.667 ms — one refresh period**, and the fine windows plus both shipping designs draw the same coverage with the same drawing commands as before (*not* byte-identical — the plan's representation changed on purpose, which `/codex-review` round 1 was right to pull up). **The story checked its own premise before the type change and nearly did not proceed**: the 69.1 ms had never been attributed, so two counts were captured on one instrument (3 194 → ≤ 16.7 ms, 50 001 → 36.1 ms, equal draw counts) and only the growth justified the rung. The sweep then **refuted the story's own single constant** — 4 000 could not be both the ≥ 3 194 floor and the ≈ 1 000 target — so `liveCoarseningThreshold` and `liveSegmentTarget` are separate. **The tail is explicitly not claimed**: p99 did not respond to the stride at any of four values, which points at the gesture-end commit and its full re-bake. **761 engine tests** (up from 736) and **200 app tests** (up from 191); ADR-030 pins the semantics and corrects ADR-029's rung-2 wording in place. **The device session then confirmed the rung and corrected the record**: at the shipped target, a sustained gesture drawing on 84 % of frames reads `med 16.670 p95 16.670 p99 33.060 max 50.008` — median *and* p95 at one refresh period against US-309's 69.1 / 118.8 — the animating path reproduces US-309's row to the microsecond, and the 3 194 control never leaves the floor. Doubling the target halves the stride and the tail does not move (worst **identical at 50.008 ms**), so on device as on the simulator the tail is not the coarse plan. **The 2026-09-05 capture the ADR had cited was mixed** — `drawn=251` is the animating signature — and the claim lands better on the clean one. Both targets reach the floor, so the shipped 1 000 is **conservative rather than tuned**, with up to double the gesture fidelity apparently free; not a knee, and left to the author. **US-313a and US-313b planned 2026-09-14**, taking the milestone to twelve stories and ~53 h: the last backlog entry from the US-309 device session is scheduled now that its stated precondition (rung 2) has landed, and **split in two** because it came in at 7–9 h against its own ~5 h estimate. Planned with `swift-architect` and `swift-ui-design`, and **the planning pass corrected nine things in the backlog specification** — the central one inverting the story. The entry named two separable causes and **the second is not a defect at all**: the frozen `startAnchor` it blames for drift is the *correct* formulation, and the live anchor it implies would be off by `(1 − m)(c₁ − c₀)`, so building it as written would have introduced the drift the entry wanted removed. The whole bug is that `StageGesture.pan` is fed from a single-touch `DragGesture`, which has no centroid; the package math is already exactly native. The entry's central premise was wrong in the same direction — the fix conflicts with **ADR-028's wording, not its substance** (the single commit's load-bearing consequence depends on `settled` not being written mid-gesture, not on `onEnded`, and ADR-028's own 2026-08-18 correction already split presentation from commit) — so the outcome is a dated amendment plus **ADR-031**, and **ADR-030 §7's inherited invariant is satisfied rather than traded**. Four scope decisions: the split; the double-tap becomes a **toggle** (fit ↔ ~2× at the tapped point) rather than reset-to-fit; **`liveSegmentTarget` rises to 2 000**, closing a final-verification item; and the **directional pan accessibility actions** come in, closing a live gap where an assistive user can zoom to 3× and never reach their design's corners. US-313b also absorbs the **tail discriminator** and the three in-the-hand judgement questions from the list below. Two planning passes disagreed on one point, and **the resolution the story wrote down was wrong** — `.live` gated on `!gesture.isIdentity` would let a bake fire at a new settled watermark mid-gesture, because `BakeKey` carries `settledCount` and not just the transform. Two tests written for ADR-028's Codex rounds 2 and 3 caught it within a minute of the gate being implemented, and AC11 is inverted. **US-313a done 2026-09-14** (PR #46): `StageManipulation` reduces two touch channels to one `StageGesture`, `StageInteraction` gains the fit ↔ 2× toggle and the directional pan, and `liveSegmentTarget` rises to 2 000. **804 engine tests**, up from 761. The in-loop reviewer **failed twice** (session limit, then a stall) and the pass was done in the main context; `/codex-review` then ran **six rounds — 22 findings, 17 fixed, 1 deferred, 4 rejected**, High → High → High → High → Medium → none valid, closing on stop condition 1 after two flat-severity escalations the author chose to continue through. **The branch's defining pattern is a three-link fix chain**: round 1's clamp caused round 4's identity-pinch defect, whose fix caused round 5's split-bounds defect, and it stopped only when the fix landed on the shared concept rather than a call site. **Round 6 re-derived US-310's own rounds 6–8 verbatim** against code that already cites them, which is a reproducibility result and a scoping warning at once — a one-constant change pulled a nine-round file back into review scope. One finding is deferred as **US-314**: while `settled` is `nil` the bake is `settled ?? fit`, so a growing run moves the stage under the user's fingers — pre-existing since US-307, and AC10 is narrowed twice rather than left claiming an invariant the code does not enforce.

**Found and fixed the same day**: `main` had **no branch protection** — the *Protect main* ruleset was `disabled` with an empty rule list, so CLAUDE.md's "branch protection keeps red out of `main`" had been untrue since M1. It is now `active` with all three CI checks required. See US-303's status block.

Goal: a minimal SwiftUI app wired end to end — pick a bundled sample program → run it with a live stage preview (needle + stitches) → export the DST through the share sheet. Proves the full thread through every layer. See [ROADMAP.md](../../ROADMAP.md).

Every story is developed test-first: the tests listed in its "Test-first plan" are written and red before implementation starts.

**Where the Catroid and Catty references disagree, [ADR-012](../../DECISIONS.md) is the arbiter** — and the app never re-implements engine semantics. Thread colour, dedup, interpolation, colour-change and layer rules stay owned by `EmbroideryStream` / `EmbroideryPatternManager` (ADR-012/013/015/020). The app only *calls* them. This is the M2 rule ("the interpreter never re-implements stream semantics") applied one layer up, and it is what decides the milestone's central design question (ADR-021).

| Story | Title | Epic | Est. | Depends on |
|-------|-------|------|------|------------|
| [US-301](US-301-bundled-sample-programs.md) | Bundled sample programs as a package product | E6 (thin) | ~4 h | — |
| [US-302](US-302-preview-core.md) | Preview core: colour-resolved stitch events, display list, transform math | E4 | ~5 h | US-301 |
| [US-303](US-303-app-target-rehabilitation.md) | App target rehabilitation, navigation skeleton, app CI job | E1 | ~4 h | US-301, US-302 |
| [US-304](US-304-sample-picker.md) | Sample picker | E6 (thin) | ~2 h | US-303 |
| [US-305](US-305-canvas-stitch-renderer.md) | Canvas stitch renderer, fit-to-screen, empty state | E4 | ~5 h | US-302, US-303 |
| [US-306](US-306-run-lifecycle.md) | Run lifecycle: driver, `AsyncStream`, batching, play/stop, needle | E4 | ~5 h | US-302, US-305 |
| [US-307](US-307-zoom-pan-and-accessibility.md) | Pinch-zoom / pan and the stage VoiceOver summary | E4 | ~3 h | US-302, US-305, US-306 |
| [US-211](US-211-dst-field-width-chokepoint.md) | DST serialization field-width chokepoint | E2 / E7 | ~3 h | US-210 (ADR-020) |
| [US-308](US-308-design-name-and-dst-export.md) | Design name, DST export via share sheet, exported UTType, gating | E7 | ~5 h | US-211, US-306, US-303 |
| [US-309](US-309-fifty-thousand-stitch-exit-criterion.md) | Exit criterion: 50k synthetic design at 60 fps | E4 | ~4 h | US-305, US-306, US-307 |
| [US-310](US-310-coarsen-mid-gesture-draw-plan.md) | Coarsen the mid-gesture draw plan (ADR-029 rung 2) | E4 | ~5 h | US-309 |
| [US-313a](US-313a-manipulation-as-a-package-value.md) | The manipulation is a package value: centroid pan, latched pinch, one commit | E4 | ~4 h | US-307, US-310 |
| [US-313b](US-313b-two-fingers-reach-the-stage.md) | Two fingers reach the stage: recogniser pair, a11y gap, tail discriminator | E4 | ~4 h | US-313a |

**Total: ~53 h.** Order: 301 → 302 → 303 → 304 → 305 → 306 → 307 → 211 → 308 → 309 → 310 →
313a → 313b.

**Two stories joined the milestone after it was planned**, both from device sessions rather than
from planning: **US-310** on 2026-09-03 (US-309's measurement left the exit criterion unmet on one
path and named the work that fixes it) and **US-313a/b** on 2026-09-14 (specified in
[`backlog.md`](../backlog.md) on 2026-09-02 from the same session, scheduled once its stated
precondition — rung 2 — had landed, and **split in two** at planning because it came in at 7–9 h
against its own ~5 h estimate). The table rows for US-310 were missing until 2026-09-14; added
here with US-313's.

**US-211 and US-313 keep their IDs.** Both were specified at discovery time and parked in
[`backlog.md`](../backlog.md); this milestone assigns them a place. The IDs are stable so the
ADR-020, ADR-030 and journal references that already cite them keep resolving. US-313's split
uses `a`/`b` suffixes rather than a new number for the same reason.

## Buildability — every story's symbols exist at or before its place in the order

Checked deliberately rather than assumed: M2's planning round shipped a story order that was *not* independently buildable (US-201 referenced a `Brick` type landing one story later) and a cross-vendor review caught it one layer down. The claim per story:

| Story | Creates | Consumes (from) | Verdict |
|---|---|---|---|
| US-301 | `Samples` target, `SampleLibrary`, `SampleProgram` | `ProgramModel` (M2, shipped) | ✅ zero prerequisites |
| US-302 | `StagePreview` target, `StitchDisplayList`, `StageTransform`, `StageGeometry`, `RunBatch`, `PreviewStitch`; `InterpreterEvent.stitch(…color:)`; `EmbroideryPatternManager.threadColor(for:)`; `EmbroideryStream.requiresTraversal` | `SampleLibrary` (301), M2 engine + interpreter | ✅ no forward references |
| US-303 | app shell, `RootView`, String Catalog, CI job | `Samples` (301), `StagePreview` (302) | ✅ **position forced** — see below |
| US-304 | `SamplePickerView`, the current-selection value | `SampleLibrary` (301), `RootView` (303) — **and nothing from US-306** | ✅ corrected in Codex round 1 |
| US-305 | `StagePreviewRenderer`, `CanvasStitchRenderer`, `SettledRaster` | display list + transform (302), app shell (303) | ✅ |
| US-306 | `InterpreterDriver`, `RunState`, `RunViewModel`, `RunPacing` | `RunBatch.reducing` (302), `StageView` (305) | ✅ |
| US-307 | gestures, `StageAccessibility` | transform methods, `bounds`/`colorRuns` (302), `StageView` (305), `RunState` + the export model (306) | ✅ — dependency on 306 was missing from the first draft (Codex round 1); its position after 306 was already correct |
| US-211 | throwing `DSTFile.init`/`DSTHeader.init`, `DSTSerializationError` | `DSTHeader`, `DSTFile`, `EmbroideryStream` — all M1 | ✅ **freely movable** |
| US-308 | `DesignName`, `DSTDesign`, `DSTFileWriting`, UTType declaration | throwing init (211), `exportModel` (306), Info.plist (303) | ✅ |
| US-309 | `SyntheticDesign` | everything render-side (302, 305, 306, 307) | ✅ |

Two places the order is **forced**, both worth stating so a later reader does not "tidy" them:

1. **US-303 comes after US-301 and US-302, even though it is narratively "story 1".** `*.pbxproj` changes are a human Xcode session (CLAUDE.md), and that session links package *products* — so `Samples` and `StagePreview` must already exist in `Package.swift` or the session has to be repeated three times. A pleasant side effect: the milestone opens with two package-only stories that run entirely under the existing `swift test` gate.
2. **US-301 comes before US-302.** US-302's display-model-vs-export-model test needs a real program to run, and SwiftPM forbids a test target depending on another test target — so `StagePreviewTests` cannot reuse `InterpreterTests`' `polygonProgram`. With 301 first, US-302's fixtures are `SampleLibrary.all` and no fourth hand-rolled program builder gets written.

US-211's freedom is genuine slack: it touches nothing M3 creates, and nothing M3 creates touches it before US-308. If the milestone runs hot it can move to position 1 and be done while the app-side design settles. It must not slip past US-308.

## Milestone exit criteria

End-to-end sample → preview → DST works; a synthetic 50 000-stitch design animates at 60 fps on an A15-class device; zoom/pan transform math is unit-tested. The transform-math criterion is met under `swift test` with no simulator, because `StagePreview` is a Foundation-only package target (ADR-022).

**Status of the 60 fps criterion after US-309 (2026-09-02): answered, and answered "half no".** Measured on an iPhone 17 Pro in a Release build, over drawn frames only: animating to 50 000 **passes clause 1** (p99 16.670 ms; the "no frame > 33.3 ms" clause is **untested by this instrument** — ADR-029 amendment, 2026-09-18), and **mid-gesture fails** at a median of **69.1 ms** — about 14 fps. ADR-009's bet holds where it was claimed and fails on the path ADR-028 created when it removed the mid-gesture blit. The failure is decisive despite the hardware being newer than the criterion asks: a pass on an A19 would prove nothing about an A15, but a fail cannot be blamed on the device. **The milestone cannot claim this criterion met until the mid-gesture path is fixed** — ADR-029's fallback ladder, starting at rung 2 (the data makes rung 1 irrelevant, since the gesture path never bakes).

**Update after US-310 (2026-09-03): rung 2 has landed, and the criterion is still not claimed — for a reason worth stating precisely.** Coarsening moves the *median* mid-gesture frame at 50 001 stitches from 36.129 ms to **16.667 ms, one refresh period**, measured on the simulator with the same instrument, the same protocol and an equal draw count. Two things keep that from being the criterion: it is a **simulator** number, and the device read **69.1 ms where this instrument reads 36.1** — roughly 1.9× — so the shipped target may need to come down on hardware; and the **tail is unimproved and is not the coarse plan** (p99 moved 46.7 / 52.9 / 49.2 across four stride values with no ordering, which is what a cost independent of the stride looks like). The remaining suspects are the gesture-end commit and the full re-bake it triggers — rung 1's and ADR-029's Θ(n²/chunk) territory. So the criterion now needs the [US-310 device session](../../us-310-device-handoff.md), whose protocol includes a no-new-code discriminator for the tail, and then the A15 confirmation below.

**Device confirmation (2026-09-05, capture 1 of 4): the median holds on real hardware.** `n=1122 drawn=251 60Hz med 16.670 p95 24.089 p99 29.068 max 43.661@7.8s`, against ADR-029's mid-gesture row of 69.1 / 118.8 / 136.2 / 166.2 — **the median mid-gesture frame is one refresh period on an iPhone**, and the p99 improved fourfold without being aimed at. It still reads **FAIL on the bar**, and only on the tail, which is exactly what ADR-030 declines to claim. The same session found the coarse plan **cutting the corners of a fill** — the hatch's edges frayed into comb teeth, mid-gesture only — fixed by a corner rule and re-confirmed on device on 2026-09-14.

**Device session complete (2026-09-14): all four captures taken, and the criterion is still not claimed — now for one reason only.** At the shipped target, a sustained gesture (`drawn=967` of 1152 over 19.4 s, 84 % of frames) reads `med 16.670 p95 16.670 p99 33.060 max 50.008` — **median and p95 both at one refresh period**; the animating capture reproduces US-309's row to the microsecond (`drawn=251`, worst 16.702 against 16.703); the 3 194 control never leaves the floor. A second value, target 2 000, reads `med 16.669 p95 16.670 p99 33.338 max 50.008`, so **both targets reach the floor and the tail is indifferent to the stride** — worst frame *identical* at 50.008 ms, three refresh periods, which on device confirms the simulator's finding that the tail is not the coarse plan.

**Correction to the block above**: the 2026-09-05 capture it cites was **mixed**, not a sustained gesture — `drawn=251` is the animating draw signature, matched exactly by this session's animating capture — so its median was computed mostly over animating frames and its p95 of 24.089 is not a mid-gesture p95. The clean capture supports the same claim more strongly. Corrected in ADR-030 rather than silently restated here.

**What keeps the criterion unclaimed is the tail**: every mid-gesture capture still reads FAIL, with a worst frame of three refresh periods. That is the **gesture-end commit and its full re-bake** — rung 1 and ADR-029's Θ(n²/chunk) territory, not this rung's, and ADR-030 claims nothing about it. The A15 item below is unchanged, and the cheapest next evidence is the **tail discriminator** the hand-off names (one unreleased gesture against several short drags), which this session did not take.

## Design summary

Decided in the M3 planning session (2026-08-04) with `swift-architect`, grounded in the Catroid canonical implementation, Catty prior art, and the M1/M2 package API. Two ADRs are pinned at planning time because US-302's tests are written against them; four more are reserved for the stories that discover them.

- **The app renders from colour-resolved events into an append-only display list** (ADR-021). `InterpreterEvent.stitch` gains `color: ThreadColor`, supplied by a new read-only `EmbroideryPatternManager.threadColor(for:)`. The alternative of calling `assembledStream()` per frame was **measured, not assumed** — 0.64 ms at 50k stitches in release **on an M-series Mac**, i.e. **3.8%** of a 16.67 ms frame and comfortably affordable. *(Corrected 2026-09-02 with ADR-021: this said "roughly 10% of a frame on A15-class hardware", which was wrong twice — the figure is a Mac measurement the text did not label, and 0.64/16.67 is 3.8%, so the sentence applied an unstated ~2.6× Mac→A15 extrapolation on top of an unstated platform. The A15 counterpart is a US-309 hand-off item and does not exist yet.)* It was rejected on structure: `assembled()` iterates `layerOps.keys.sorted()` and emits layer boundaries lazily, so for a **multi-layer** program a new stitch inserts into the middle of the returned array, which forecloses ADR-009's "rasterise the settled prefix, redraw only the live tail". (For a single-layer program the prefix *is* stable — the point is not to bet the architecture on never having two objects.) Tracking colour in the app was rejected because it duplicates ADR-015's four rules, and Catty's prior art shows the concrete failure: its per-batch colour reset mis-colours the batch-boundary seam.
- **Two new app-support targets in the engine package** (ADR-022): `Samples` (depends on `ProgramModel` only) and `StagePreview` (depends on `Interpreter` + `EmbroideryEngine`, Foundation-only — no SwiftUI, no CoreGraphics). This keeps the display list, the transform math and the event reducer under `swift test` and the existing pre-commit gate, and lets M5 inherit the samples rather than redo them. The ADR-016 dependency DAG stays a straight line inward.
- **`StageGeometry` puts ADR-007's 500×500 stage into code for the first time.** Its doc comment must say that it does **not** bound engine input — nothing bounds a `StagePoint`, and a design can legitimately leave the stage. The stage is drawn as a hoop outline and is not clipped to, so an out-of-hoop design is visible rather than silently cropped.
- **The interpreter runs off `@MainActor`** in a cancellable `Task`, looping `step()` — not `run(maxTicks:)`, which cannot break on a *stitch* budget. One tick can emit 51 stitches in sample 1 and **132** in a triple-stitch design (this paragraph said 106 until US-306's implementation corrected it against `SampleBudgetTests`' pinned literal — see that story's criterion 3), and there is **no fixed upper bound**: `step()` sums every runnable thread's events into one atomic batch, and a single thread's worst case is 3 000 002 events (one `.needleMoved`, the first anchor, and 3 × ADR-014's 1 000 000 *segment* cap, since triple stitch emits three points per segment). So the frame budget governs tick count, not batch size — see US-306. Batches cross to the main actor through an `AsyncStream` with unbounded buffering, and the view model performs **exactly one** observable mutation per batch.
- **`InterpreterClock(tickDelta: 1.0/60.0)` with one tick per frame**, so a `wait(1)` brick occupies 60 ticks ≈ 1 s of wall time and looks right on screen with no wall-clock anywhere in the package (ADR-018).
- **The terminal batch always carries `assembledStream()`** — on natural finish, on the stitch cap, *and* on cancellation. That is the direct fix for Catty's hazard where `Stage.stopProject()` tears down the graph `shareDST` reads; export after a user stop is safe by construction and is an explicit acceptance criterion, not an accident of value semantics.
- **The renderer sits behind a protocol with `associatedtype Body: View`**, not a `GraphicsContext` parameter — a context in the signature *is* the Canvas leaking into the protocol and would defeat ADR-009's Metal escape hatch.
- **Export gates on the post-replay `assembledStream().count > 1`**, not on `hasValidPattern` (which counts recorded ops the replay may reject). This closes the divergence ADR-020 left "for whoever wires up export to decide", and matches Catroid's `validPatternExists()`, which counts points in the *built* streams.
- **`DSTFile.init` and `DSTHeader.init` become throwing** (US-211, ADR-025). Both are public, so both trap today; 33 call sites gain `try`. Throwing rather than failable because the export path must tell the user *which* limit was hit, and `Optional` cannot carry that.

## Documented deviations from the references

Deliberate, and every one is an improvement on a reference defect rather than a shortcut:

| Deviation | Why |
|---|---|
| Jump traversals drawn distinctly from thread | **Both** references draw them as solid thread indistinguishable from stitching (Catroid suppresses lines only across colour changes; Catty's `drawStitchingLine` is unconditional), so a machine's travel moves look sewn. Needs `EmbroideryStream.requiresTraversal` so the app asks the engine instead of re-deriving ADR-020. |
| Needle indicator is our own design | Neither reference has one: Catroid's "needle" is an ordinary sprite with a PNG look; Catty has zero occurrences of "needle" in `src/`. No parity obligation — judged on ADR-009 cost and accessibility. |
| Per-colour-run `Path` grouping | Catroid sets `shapeRenderer.color` per primitive because libGDX vertex colours don't break the batch; SwiftUI `Canvas` needs the grouping. Forced by the API, not a semantic change (ADR-009). |
| Fixed logical tick, no adaptive sub-stepping | Catroid runs `stage.act()` up to **50×** per frame and *increases* the count when the pass is fast (`deltaActionTimeDivisor`, `StageListener.render():576-600`) — an anti-throttle that fights its own O(n)-per-frame rebuild. ADR-018's fixed tick plus an explicit stitch budget replaces it. |
| Display list built from ops; export model from the replay | Clause C/D re-emits and interpolation intermediates are duplicates or on-segment points, so those leave the drawn path identical and differ only in record sequence. **Clause B is stronger**: it emits two records at the previous actor's position in explicit black, with no counterpart in the display list, so a multi-actor design's export and preview differ in *colour* (ADR-021). M3's samples are single-object, so it is not user-visible this milestone. Catroid needed `EmbroideryExportIsolationTest` for the same separation; ours is a deliberate invariant with its own test (US-302). |
| Every display-list entry is dotted | Catroid skips dots on jump and colour-change points, but those are synthetic *export-model* records — `isJump`/`isColorChange` exist only on assembled `Stitch` values, and the display list holds only stitches **the program requested**. Deliberately not "real penetrations": under ADR-020 an op can be recorded and drawn while the replay rejects it, so the machine never goes there (`placeAt(1e300, 0)` then `stitch`). A record-model difference, not an appearance one; the visual work Catroid's flags did is carried by segment styling instead (US-305). |
| Segment suppressed across a colour-run boundary | **Not** Catroid parity, though an earlier draft said so: Catroid's latch resets on the next connecting point and it then draws a black connector across the swap. Our display list has no black transition point, so drawing anything there would imply continuous thread where the machine stopped (US-305). |
| Export gate and render gate may legitimately disagree | Catroid keeps one predicate for both, so "nothing rendered" and "nothing exportable" agree. For us they can diverge exactly in ADR-020's rejected-coordinate case: ops recorded and drawn, every one rejected at replay. The app says so specifically rather than offering a header-only file — Catty ships a 515-byte header-plus-EOF file with zero stitches. |
| Design name validated, not silently truncated | Catroid `take(15)`s the project name, never validates it, and mangles non-ASCII to `?` bytes under `US_ASCII`; Catty's shipping app exports an **always-blank** `LA:` field (only its tests pass a name). There is no working precedent on either platform. |
| File name sanitised independently of the header label | They are unrelated fields in the format. Catroid's `sanitizeFileName` has no empty check and yields a file literally named `.dst`. |
| Exported UTType for `.dst` | Catty declares none — it ships bare temp URLs that resolve to `public.data`/`dyn.*`, and Catroid sets `type = "text/*"` for a binary file. The `.catrobat` declaration in Catty's `App-Info.plist:102-123` is the only structural template. |
| `RunState` has no `failed` case | ADR-018 guarantees the interpreter never halts — every bad-formula path continues with a per-brick fallback and `FormulaError.notANumber` is caught, not propagated. Nothing in the run path can fail, so `failed` belongs to the *export* lifecycle, which really can. Corrects ROADMAP.md's four-case enum rather than shipping a case with no producer. |

## Human Xcode hand-off (prerequisite for US-303)

`*.pbxproj` is human-only (CLAUDE.md). US-303 cannot start until these are done, in this order. All are verified findings, not speculation — the app target is still the Xcode template and contradicts three ADRs.

1. **Link five package products** to the app target: `EmbroideryEngine`, `ProgramModel`, `Interpreter`, `Samples`, `StagePreview`. Currently **zero** are linked (`grep -c EmbroideryEngine project.pbxproj` → 0).
2. **`IPHONEOS_DEPLOYMENT_TARGET`: 26.5 → 17.0** (ADR-004). Nothing in M3 needs more: `Canvas` is iOS 15, `ShareLink` iOS 16, `@Observable` iOS 17.
3. **`SWIFT_VERSION`: 5.0 → 6.0.** Keep `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES` — they are literally ADR-006's shape. Note in review that the app target's isolation defaults therefore differ from the package's.
4. **`PRODUCT_BUNDLE_IDENTIFIER`** on all targets: `temp.catrobat-embroidery-ios` → the real reverse-DNS id.
5. **Create a real `Info.plist`** and point `INFOPLIST_FILE` at it (`GENERATE_INFOPLIST_FILE` stays `YES` for the generated keys). Required because `UTExportedTypeDeclarations` is an array of dicts with no `INFOPLIST_KEY_*` form. Once the file exists, US-308 edits its XML freely — that is not a pbxproj change.
6. **Add `Localizable.xcstrings`** to the app target. `LOCALIZATION_PREFERS_STRING_CATALOGS` and `STRING_CATALOG_GENERATE_SYMBOLS` are already `YES`; only the file is missing.
7. **Share the scheme** (Manage Schemes → Shared) so `xcshareddata/xcschemes/` is committed. It does **not exist** today — `xcodebuild -list` finds a scheme only because Xcode autocreated it locally, which a fresh CI checkout cannot be relied on to do.
8. **Delete the `catrobat_embroidery_iosUITests` target.** XCUITest requires XCTest, which CLAUDE.md forbids; the UI definition of done uses XcodeBuildMCP screenshots instead. Accepted cost: no `XCTApplicationLaunchMetric` launch metrics in M6.
9. **Delete the template `ContentView.swift`.**

## Definition of done

Every UI story inherits [ROADMAP.md](../../ROADMAP.md)'s M3+ definition of done in full (String Catalog with translator comments, leading/trailing layout, loading/empty/error states shipped with the feature, Reduce Motion, VoiceOver, ≥ 44 pt targets, Dynamic Type to AX1) plus a simulator screenshot via XcodeBuildMCP. Each story restates only what is *specific* to it — not the whole list.

Two clarifications that apply throughout:

- **Reduce Motion does not disable the stitch animation.** Watching stitches appear is the feature's content, not decoration. It disables transform springs and the fit-to-screen re-animation.
- **Thread colours are design data and must not adapt to dark mode.** Only stage chrome (hoop, background, grid) is semantic-coloured.

## Final verification — deferred to milestone close

Items that are **not blocking any story** and are deliberately held until the remaining M3 work
is done, so they are run once against the finished milestone rather than repeatedly against a
moving one. Recorded here at the moment each was deferred, with who owns it.

**From US-309 (device measurement, 2026-09-02):**

- [ ] **The A15-class capture.** US-309 measured on an iPhone 17 Pro (A19). That is enough to
      establish the mid-gesture *failure* — faster hardware failing cannot be blamed on the
      hardware — but not enough to *confirm a fix*. Re-run the animating and mid-gesture
      captures on A15-class hardware once ADR-029's rung 2 lands. **Rung 2 landed 2026-09-03
      (US-310)**, so this item is now unblocked; it wants the [US-310 hand-off's](../../us-310-device-handoff.md)
      captures, including the target sweep, since the shipped target is a simulator-derived
      knob and the device is ~1.9× slower on this path. **Those captures are now taken
      (2026-09-14, A19) and are in ADR-030's device table**, so what is left here is strictly the
      A15 re-run of the same protocol. **Sequencing, 2026-09-14**: run it in the same session as
      [US-313b](US-313b-two-fingers-reach-the-stage.md)'s four captures, on the A15 device. The
      protocols share an instrument and a design, so one sitting answers both — and doing it
      after US-313b rather than before means the A15 confirmation is taken against the gesture
      that will ship, not against one being replaced.
      **Still open after the 2026-09-18 session, deliberately.** That session ran the protocol
      again on the **same iPhone 17 Pro (A19)**, because no A15-class device was available. It
      re-confirms the shipped behaviour against the US-313b gesture — and the mid-gesture capture
      is the cleanest yet (`drawn=987/1018`, `max 38.076 ms`, `commits=1`; see the screenshots
      item) — but **A19 passing says nothing about A15**, which is the whole point of the item, so
      it is not ticked. What that session *did* close is the Instruments item and the screenshots
      item below, and it found the display-link instrument's blind spot recorded in ADR-029's
      amendment. A future A15 session should read that amendment first: the capsule's verdict
      alone is not sufficient evidence for the bar's second clause on the animating path.

- [x] **The tail discriminator** — **reassigned 2026-09-14 to
      [US-313b](US-313b-two-fingers-reach-the-stage.md) (AC12, capture 2)**, not run here. It is
      the cheapest evidence for the claim both ADR-029 and ADR-030 rest their tail argument on:
      one capture holding **a single gesture that is never released** (no commit, so no re-bake)
      against one with several short drags. If the tail follows the number of gesture *ends*
      rather than drawn frames, it is the commit, and the residual belongs to rung 1. Three
      reasons it moved rather than stayed: US-313b **changes the variable it measures**
      (gesture-ends per unit of user activity), so a before/after is only interpretable if it is
      run on both sides; the sustained capture becomes a single two-finger manipulation instead
      of the alternating sequence ADR-030 had to discard once for carrying the animating
      signature; and US-313b adds a `#if DEBUG` `StageCommitCounter` that makes it an
      **observation** rather than an inference.

- [x] **The three in-the-hand judgement questions** — **reassigned 2026-09-14 to
      [US-313b](US-313b-two-fingers-reach-the-stage.md)** (human checks, item 6), not run here:
      the coarse image at **two zoom levels** (the edges and the colour-band boundary, since the
      corner fix has only been confirmed at one), whether the fidelity **pop** at gesture start
      and commit is distracting, and whether the **stride discontinuity** at
      `liveCoarseningThreshold` shows up in practice (a 4 001-stitch design strides by 5, a
      4 000-stitch one by 1). They move because all three are judgements *about a gesture*, and
      US-313b is where the gesture becomes worth judging — asking them of the shipped
      single-touch pan would answer a question about interaction that is about to be replaced.

- [x] **Whether to raise `liveSegmentTarget`** — **decided 2026-09-14: raise it to 2 000.** An
      author's call, not a measurement, and Sebastian took it during US-313 planning. Target
      2 000 holds the median and p95 on device exactly as 1 000 does, so up to double the
      gesture fidelity appears to cost nothing; but both readings sit on the instrument's floor,
      so this was evidence that raising it is *free*, not a located knee. The constant changes in
      [US-313a](US-313a-manipulation-as-a-package-value.md) (AC16) on that simulator-and-device
      evidence and is **re-verified on device in [US-313b](US-313b-two-fingers-reach-the-stage.md)
      (AC13)** under the new gesture, since a gesture that tracks properly may raise the
      touch-move rate and therefore the draw rate. It also does real work there: it halves the
      magnitude of the fidelity pop, which matters more once gestures are held longer.
- [x] **Instruments (Animation Hitches) traces** — **done 2026-09-18**, and they earned their
      billing as "the only artefact that observes the rendering pipeline directly rather than
      inferring it from display-link timing": **they contradict the display-link instrument on the
      animating path.** Paired with a capsule capture over the same frames, a run the capsule
      scored `p99 16.670 · max 16.702 · PASS` shows **36 hitches, 22 over 33.3 ms, 107.4 ms/s**,
      and the panel presenting **51 frames/s against 60 Hz**. Observer overhead excluded — under
      the profiler the capsule reproduces US-310 capture 09 to three decimals. Cause, consequence
      and the deliberate decision to change **no code** are in **ADR-029's amendment**; the
      reproduction protocol, including four pieces of tooling friction that cost this session
      time, is appended to [`us-309-device-handoff.md`](../../us-309-device-handoff.md). Every copy
      of the "no dropped frame" verdict is narrowed to clause 1; the bar itself is **not** reworded
      (AC8).
- [x] **The zoomed 50k screenshot, plus capsule screenshots of the animating and mid-gesture
      captures** — **done 2026-09-18**, all three on the iPhone 17 Pro:
      [`04-device-50k-zoomed.png`](../../screenshots/us-309/04-device-50k-zoomed.png),
      [`05-device-50k-animating-capsule.png`](../../screenshots/us-309/05-device-50k-animating-capsule.png)
      (the run paired with Instruments) and
      [`06-device-50k-mid-gesture-capsule.png`](../../screenshots/us-309/06-device-50k-mid-gesture-capsule.png).
      The mid-gesture capture is the first on device since US-313a raised `liveSegmentTarget` to
      2 000 and US-313b replaced the gesture, and it is a **better** capture than US-310's
      capture 12 on both axes: `drawn=987/1018` (**97 %** against 84 %, so almost no animating
      frames are mixed in) with `max 38.076 ms` against 50.008 ms, at `commits=1`. Still FAIL on
      the tail, as expected — the tail has never been claimed. It is also the capture that
      **refuted the first draft of ADR-029's amendment**, within the hour of it being written.
- [x] **Two criterion-level questions, for the author to rule on** — **both ruled 2026-09-18**;
      the rulings and their reasoning are in ADR-029. In short: (1) the bar stays **exactly as
      written** and the `p99` clause is recorded as non-discriminating rather than dropped, since
      dropping it would be rewording a criterion in response to a measurement and the 2026-09-18
      session is itself a measurement; (2) the `NO DRAWS` label stays, extended by a caveat rather
      than by code, because the animating capture shows the weaker case a draw count cannot catch
      — `drawn=251`, a real workload, passing while 22 frames exceeded 33.3 ms. Standing
      consequence: **a capsule `PASS` is never on its own sufficient evidence for the bar's
      dropped-frame clause.** No code changed.

      *The questions as originally recorded, kept verbatim:* Both recorded in ADR-029 and
      deliberately *not* acted on, because AC8 forbids rewording a criterion in response to a
      measurement. (1) The `p99 ≤ 16.67 ms` half has **no discriminating power at 60 Hz**: the
      same scenario read `FAIL` then `PASS` across two captures, decided in the third decimal by
      display-link jitter about a 16.6667 ms period. The informative half is the 33.3 ms
      dropped-frame check. (2) A capture in which the renderer never runs **satisfies the
      numeric bar** — handled today by labelling (`NO DRAWS`) rather than by the bar itself.

**From US-307 (accessibility, deferred by design):**

- [x] **The manual accessibility pass** — VoiceOver, Dynamic Type to AX1, Reduce Motion — run
      **once over all M3 UI** rather than per story, and recording explicitly what could not be
      run. `simctl ui` exposes neither VoiceOver nor Reduce Motion, and the toolchain has no
      pinch preset, so parts of this are human-only. **Must run after
      [US-313b](US-313b-two-fingers-reach-the-stage.md)**, which changes the stage's interaction
      layer, and its checklist gains two items from that story: that the stage is still exactly
      **one** accessibility element once a `UIViewRepresentable` sits in the tree (AC8), and that
      the four new **directional pan actions** are reachable and speakable (AC9). The second
      closes a gap that is live in the shipped app today — `StageInteraction.adjust` anchors on
      `viewport.center`, so an assistive user can zoom to 3× and never reach their design's
      corners.
      **Run 2026-09-18 on an iPhone 17 Pro (iOS 27.0), Release build. Result: pass, with one
      caveat and one procedural correction.**
      - **AC8 — the stage is exactly one element: PASS.** Swiping lands on it once and moves past;
        VoiceOver never steps into stitches or sub-parts, with the `UIViewRepresentable` in the
        tree.
      - **AC9 — the four directional pan actions: PASS, via the rotor.** All five custom actions
        are present and speakable in the order ADR-031 predicts — **Fit to Hoop, Pan Left, Pan
        Right, Pan Up, Pan Down** — and activating Pan Left moves the viewport left so the design
        slides right, confirming the camera-relative convention. **Procedural correction worth
        keeping**: the first attempt reported the actions as *unreachable*, because the test asked
        for a swipe up/down. On an `Adjustable` element that gesture is increment/decrement — it
        zooms, exactly as it should — and custom actions are only reachable by rotating the rotor
        to "Actions" first. ADR-031 already records that `Activate`/`Increment`/`Decrement` are
        implied by the trait and are not custom actions; the test procedure had not absorbed it.
        **The finding was in the test, not the app.**
      - **Stage value: PASS** — stitches / colours / millimetres, spoken only once the run is
        final.
      - **Reduce Motion: PASS on all three.** The stitch animation still runs (it is content, not
        decoration, per this file's own clarification), the double-tap zoom is instant, and the
        fit re-animation is instant.
      - **Dynamic Type: PASS at AX1**, which is what the ROADMAP definition of done requires — no
        clipping, no collision between the design-name counter and its label, nothing unreachable.
        **Caveat recorded in the author's own words**: "every size looks good — *good* is
        questionable with the biggest settings." No specific defect was named, and the sizes in
        question are **above AX1** and therefore outside the stated bar. Left as an observation
        rather than converted into a story.
      - **Not run**: nothing. The pass is complete for the M3 UI as shipped.

**Standing:**

- [x] **Knowledge-graph drift check** — **done 2026-09-18, 40 edges triaged.** No ADR was
      contradicted and no story reinvented an ADR's invariant, so the check's own question answers
      *no*. It surfaced the inverse instead: **four cross-cutting process invariants that no ADR
      owns** — criterion-non-rewording (in US-309's AC8, a story checklist), the "test that cannot
      fail" pattern (an aside in ADR-028, re-applied in ADR-025/026/027), correction-completeness
      and execute-the-premise (both in ADR-027's review section). Candidate M4 planning item: give
      them a home. The one pair that looked like genuine ADR overlap — ADR-014 ↔ ADR-017, both
      accepting a `Double` divergence — was **refuted by ADR-017's own Context**, which already
      pins the boundary; the ADR won, per the standing rule. Journalled 2026-09-18, including what
      did not run: the `workflow-journal.md` chunk failed on a session token limit, and the 33 new
      screenshots plus the just-rewritten package README were deliberately excluded. All 35 are
      unstamped in the manifest and re-queue on the next `--update`.
- [x] **`swift-documenter` pass** for package READMEs over the stabilised public API — **done
      2026-09-18.** `Packages/EmbroideryEngine/README.md` now covers all five library products
      (901 lines). Verified rather than taken on report: only that one file changed, the product
      list matches `Package.swift`, and every CamelCase symbol it cites resolves to a declaration
      in `Sources/` — the twelve that do not are five stdlib/Foundation types, three module names,
      and four **Catroid Java class names cited as AGPL provenance**, each matching the provenance
      comment in the corresponding Swift file.

## Manual Ink/Stitch verification

Needed at **US-308** (first time a file reaches a viewer through the *app* path — check the `LA:` name and the colour stops) and at **US-301** (the bundled samples' DST output). Not needed for the other eight stories, which change no bytes.

**Correction (2026-08-07, US-301 close-out)**: this paragraph originally justified the US-301 check as "since sample 1 is meant to be byte-comparable against the shipping Android app". **Android is not a byte-identical oracle for it.** Catroid computes its pattern distance as `(float) Math.hypot(...)` (`RunningStitchType.java:35-37`) and carries every coordinate as `float`, so the ~1e-14 residue that costs our sample 1 ten stitch intervals is roughly nine orders of magnitude below its resolution — the threshold behaviour producing our 3194 records cannot arise the same way there. This is ADR-014's existing "bit-exact parity with Android is not guaranteed" showing up where it is *structurally* visible rather than sub-resolution, not a new divergence. The precise consequence — a first draft of this paragraph overstated it, and Codex round 1 was right to push back — is that Android's output is **not a byte-identical oracle**: equality cannot be promised, so a mismatch is not evidence of a bug on either side. That is weaker than "byte comparison is impossible", which does not follow. A byte comparison is still worth running; it just cannot be a golden. Verbatim transcription remains correct, for the design-level comparison and the provenance; only the stated reason needed narrowing. Scoped in `Sources/Samples/Resources/PROVENANCE.md`.
