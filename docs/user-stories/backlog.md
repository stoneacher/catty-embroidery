# Backlog — specified but not yet scheduled

Stories that are fully analysed but have no milestone yet. They live here rather than in a
milestone folder so a closed milestone's "all N stories merged" claim stays true, and so the
analysis is captured while it is fresh instead of being re-derived at the next planning
session. Precedent for why that matters: the ±121 coordinate trap sat as a journal
carry-forward from 2026-07-09 to M2 planning, and was then mis-scoped twice by review before
it became US-210.

Milestone planning picks these up and assigns them a place; the ID stays stable so existing
ADR and journal references keep resolving.

---

## US-317 — A Linux engine-test job, so target isolation is structural rather than textual

**Raised by US-401's review loop (2026-09-20), not scheduled.** `EditorCoreTargetIsolationTests`
guards ADR-033's "no SwiftUI, no CoreGraphics" with a **textual scan** of the target's sources.
Three Codex rounds found six distinct *legal* Swift spellings that escaped successive versions
of it — split across lines, interrupted by a comment with and without surrounding spaces,
backtick-escaped, separated by `;`, and hidden behind a CRLF line ending — and the reviewer's
own conclusion is that the scan "cannot claim to cover every legal spelling" (a NUL byte
between `import` and the module name compiles with a warning and is not matched by `\s`).

**This is ADR-023's documented failure shape**: a text classifier asked to be exhaustive, where
each fix enlarges the surface it defends. ADR-023's own ending is the precedent — *asking the
working tree instead is what ended it.*

**The structural answer exists and is cheap to state**: run the engine tests on Linux as well as
`macos-26`. SwiftUI, UIKit, CoreGraphics and AppKit **do not exist there**, so importing any of
them is a hard compile error — total, regex-free, and it guards every package target at once
rather than only `EditorCore`. The manifest half of the same criterion already made this move
successfully in US-401: the textual pin was replaced by `swift package dump-package` in CI once
it was clear that a proxy for an evaluated fact cannot be repaired, only replaced.

**Why it was not done inside US-401**: it is a CI-wide change with its own unknowns, not a story
line item. The package must actually *build* on Linux — `Samples` ships localized resources
through `Bundle.module`, and Foundation on Linux is not Foundation on Darwin. That is a spike,
and its first deliverable is a yes/no answer rather than a job.

**If it is never taken**, the cost is bounded and should be stated rather than assumed: the scan
still catches every spelling an ordinary source file can express, which is the actual threat
model — an import *creeping in* because someone reached for a SwiftUI type. Every escape found
across three rounds was a deliberately hostile construction, not a plausible accident. The
in-file comment says exactly this, so a later reader is not misled about what the guard proves.

---

## US-319 — The stage's chrome runs out of room at AX4–AX5, and nothing on it can scroll

**Found**: 2026-09-27, US-312's AX5 spot check on the iPhone 17e (the smallest simulator available).
**Pre-existing on `main`**, measured rather than inferred: `docs/screenshots/us-312/ax5-main-before.png`
is `main` at AX5 after a finished Square Coil run, and the **design-name text field is gone**. Only its
label and the `10/15` counter fit between the scrolling notices and the two pinned action rows.

**Mechanism.** `StageView` stacks the canvas (with a 120 pt floor), the scrolling `StageNotices` block
(ending with the name field) and two pinned rows (export, then transport) that never shrink. There is
deliberately no outer `ScrollView` (`StageView.canvasSlot`'s comment says why: a flexible canvas inside
a scroll view gets an unbounded height proposal). At AX5 the pinned rows plus the canvas floor exceed a
6.1-inch screen, and the notices block is squeezed to nothing. Its `ScrollView` scrolls, but the field is
the last thing in it and the first thing to disappear.

**What US-312 did about it, and what it did not.** US-312 added a caption under the Share button. Left
uncapped, it made AX5 visibly worse: the Share label spilled out of its own background
(`ax5-uncapped.png`). It is therefore capped at AX1 (`.dynamicTypeSize(...DynamicTypeSize.accessibility1)`,
Sebastian's decision, 2026-09-27). With the cap the button is intact, but the counter is half-hidden
behind it (`ax5-capped.png`). The cap stops US-312 from making things worse; it does not fix the squeeze,
which is this entry.

**Also seen, same device, default text size** (`disabled.png`): the not-yet-run empty state's title
renders as "Ready to St…", truncated inside the dashed hoop. It is a different mechanism (a
`ContentUnavailableView` in an aspect-fitted square with 24 pt insets), recorded here because it is the
same screen, the same device and the same class of problem.

**What taking it would involve.** Decide how the stage adapts when the chrome cannot fit. Candidates:
- let the pinned rows join the scrolling region above some Dynamic Type size;
- give the notices block a layout priority over the canvas floor;
- use `ViewThatFits` over a compact arrangement.

It needs a `swift-ui-design` pass and screenshots at AX3–AX5 on the smallest device, and it interacts with
US-315 (the keyboard transient) and US-409's palette sheet, both of which also take height from this
screen. **The ROADMAP's Dynamic Type bar is AX1**, which the stage meets, so this entry is below the
definition of done. That is why it is a backlog item rather than a defect in any shipped story.

---

## US-318 — The package does not build its tests in release configuration

**Found**: 2026-09-23, in passing during US-402's review. **Pre-existing on `main`**, unrelated to
that branch, and **invisible to every gate the project runs**.

`swift build -c release --build-tests` inside `Packages/EmbroideryEngine` fails:

```
error: ... Tests/EmbroideryEngineTests/CoordinateChokepointManagerTests.swift:1:8 unable to
resolve Swift module dependency to a compatible module: 'EmbroideryEngine'
error: SwiftDriver EmbroideryEngineTests normal arm64 ... failed with a nonzero exit code
```

The proximate cause is almost certainly that `-c release` disables testability while several test
files use `@testable import` (`DSTStitchRecordTests`, `DSTHeaderTests`, `DSTRecordDecoder`,
`InterpreterDriverTests`) — but **that diagnosis is a hypothesis, not a finding**: it was not
confirmed, and a cross-vendor reviewer hitting the same wall in the same session reported a
*different* failing file, so only the fact of the failure is established.

**Why it is worth an entry rather than a fix.** Nothing is masked today: the pre-commit gate, the
CI engine-test job and the app build all use debug, so no branch can be green here and broken
there. The cost is latent and narrow — anyone who reaches for a release build to time something
(which is exactly how it surfaced: an attempt to speed up a fuzz run) loses the session to
diagnosing it instead. That is a small cost paid rarely, which is the definition of a backlog item
rather than a story.

**What taking it would involve**: decide whether release-configuration test builds are something
this project wants at all. If yes, the `@testable` uses need auditing — US-401's
`EditorCoreTargetIsolationTests` comment already argues that `@testable` is used here sparingly and
with a stated reason each time, so the audit is small. If no, the honest outcome is a line in the
README saying debug is the supported configuration, which costs nothing and stops the next person
rediscovering this.

**Not** to be taken as a reason to remove a `@testable` that earns its place. `InterpreterDriverTests`
documents why it needs one, and a release build is a weaker claim than that test.

---

## US-321 — A loop's end row wears the Undo glyph

**Found**: 2026-09-29, US-408's simulator pass (flagged by the `swift-ui-design` pass). US-407 gave `loopEnd`
rows `arrow.uturn.backward`; US-408 put an Undo button in the bottom bar with the same symbol, a few
centimetres below. A structural marker now reads as a command, and a user may tap it expecting an undo.
- The row is not a control, so nothing breaks. The cost is legibility, which matters more to a child user.

**What taking it would involve.** Pick a structural symbol for the end row, such as `return` or
`arrow.turn.left.up`, in `ScriptRowView.symbol(for:)`. Re-take US-407's list screenshots. This is a
design call, so it gets a `swift-ui-design` look, and no test pins the symbol today.

---

## US-322 — The settled raster is never composited in the stage's default layout on iPhone 17

**Found**: 2026-10-01, US-315's simulator probe. **Severity: performance, possibly large.** In the
measured configuration it cancels ADR-009's cache and wastes the bake work on top.

**What was measured.** On iPhone 17 (a 3× screen), with the export row showing:
- The `GeometryReader` measures the stage viewport as **370 × 256.833…** pt.
- The `Canvas` inside it is handed `size` **370 × 257.0**.
- `CanvasStitchStroke.compositingRaster` (via `CanvasStitchLayers.matches`) compares the two for
  exact equality, so the raster gate fails on **every** frame.
- One full run of the 50k fixture: **251 of 251** stitch draws took the full-stroke path, and
  `rebakeIfWorthwhile` baked **51 times**, every bake thrown away.
- In the layout without the export row (309 pt, integral) the raster composites normally.

That explains a curiosity in US-315's first probe pass: focusing the name field produced a re-bake
with an unchanged viewport. It was the first frame in which the raster could be used at all.

**Why it may matter beyond this configuration — unmeasured.** It is measured for one layout only:
iPhone 17, default text size, export row showing. Whether other fractional viewports get a
differently rounded `Canvas` size is **not established**; SwiftUI may round both the same way
elsewhere. Measuring that is the first step of taking this story. ADR-029's device measurements may have been taken in a configuration that happened to be
integral. If so, the numbers describe the cache working on a screen where, in practice, it rarely
does. Worth re-checking against the US-309 capture notes before deciding priority.

**What taking it would involve.**
- Decide what the raster is keyed on:
  - the `Canvas`'s own `size` (baking at the size the frame is drawn into), or
  - a pixel-rounded viewport, or
  - a tolerance in `matches` of less than one device pixel.

  The first is the most honest, since the size check exists to stop a stretched blit. But `size`
  is only known inside the `Canvas` closure, while the bake runs from `onChange`, so the key needs
  a measured size.
- A test first: `CanvasStitchStroke.compositingRaster` is already a pure function under
  `CanvasStitchStrokeTests`, so a red case with a fractional viewport against a rounded `size` is
  straightforward.
- Then re-measure the 50k frame times on device (ADR-029's procedure) and record the difference.

---

## US-323 — A repeat reached mid-tick reads its count a tick before Catroid does

**Found**: 2026-10-18, by `swift-code-reviewer` on Brick backend slice 3 (sensors), confirmed with a probe.
**Scheduled and done**: 2026-10-20, Variables slice 4 (ADR-018 amendment). The analysis below held exactly: the probe now ends at (2, 3), and the one predicted shift — a script ending in such a loop finishes a tick later — is the only one; no golden moved.
- **The mechanism:** `enterRepeat` runs with `deferEntry` when an action already ran this tick. If the loop has no counter yet, it still evaluates `times` this tick.
  - A count ≤ 0 exits immediately on tick t's state.
  - A positive count is discarded and re-read at t + 1.
- **What Catroid does:** `RepeatAction` reads its count on its own first `act`, at t + 1 (libgdx `SequenceAction` advances one child per tick).
- **The probe:** object scripts A = `[setY(1), repeat(objectX) { changeYBy(1) }]` and B = `[setX(2)]`.
  - Here, A reads objectX = 0 in tick 1, before B runs, skips the loop and ends at (2, 1).
  - Catroid reads 2 in tick 2 and ends at (2, 3).
- **Not new with sensors:** a project variable written by a later script took the same route before. Sensors add the shared needle. ADR-018 does not mention it.

**What taking it would involve.**
- When `deferEntry` and no counter exists, yield before evaluating.
- The only other shift is that a script ending in such a loop is marked finished one tick later. That touches ADR-018's same-tick-finish rule, so it needs an ADR-018 amendment and a check that no golden's event timing moves.
- Kept out of the Brick backend feature because it changes interpreter scheduling, not the brick vocabulary.

---

## US-324 — The program document drops an unknown key that sits beside a known one

**Found**: 2026-10-18, while verifying Codex handover round 3 of Brick backend PR 1. Probed directly.
- **The behaviour:** Swift's synthesized `Codable` builds an enum's keyed container from the keys it *knows*, and a struct ignores fields it does not declare. So `{"rand":{},"sin":{}}` decodes as `sin`, `{"leaf":{"_0":1},"bogus":{}}` as `leaf(1)`, and `{"a":1,"extra":2}` as `Box(a: 1)`. An unknown key on its own is refused, as ADR-037 intends.
- **Scope:** this holds for the whole v1 format since US-404, for every enum and struct, and is not specific to the new formula vocabulary.
- **Why it matters:** ADR-037 is titled "refuse what you do not understand", and a hand-edited file loses the unknown part silently, so the next autosave writes the file without it.
- **Why it is not urgent:** a future build adding vocabulary bumps the format version under the freeze rule (ADR-037's 2026-10-18 amendment), and the old reader refuses it on the version probe before it reaches the shape. App-authored files never contain such keys; only hand-edited, corrupted or externally produced files reach this path.

**What taking it would involve.**
- Strict-key decoding, either through a decoding pass that compares each container's `allKeys` against the raw JSON object's keys, or through a pre-decode walk of `JSONSerialization` output against the schema.
- Pin it with fixtures that place an unknown key beside a known one at each level: program, scene, object, script, brick, formula, and the vocabularies.
- It is an ADR-037 amendment, since admission gets stricter.

---

## US-325 — The engine's `javaRound` is not quite Java's `Math.round`

**Found**: 2026-10-17, by `swift-architect` probing the brick backend's math premises under `jshell` (Java 17). Filed at the feature's close, as its brief lists.
- **The behaviour:** the engine rounds every stage coordinate with `javaRound`, `floor(x + 0.5)` (`Geometry.swift`, ADR-012). Java 7+ `Math.round` is not that expression. It gives 0 for 0.49999999999999994, where `0.49999999999999994 + 0.5` rounds up to 1.0 before the floor. It also differs near 2⁵², where `x + 0.5` is not representable.
- **Already handled for formulas:** the `round` function follows Java 7+ (ADR-046 divergence (d)), so a program's `round(…)` matches Catroid.
- **Why it is not urgent:** for coordinates the gap is sub-resolution, ADR-019's class. A stage value one ulp below a half unit is not a design anyone draws, and 2⁵² stage points is far outside ADR-007's 500 × 500 stage.
- **Why it is recorded:** ADR-012 and the `javaRound` doc comment both state "Java `Math.round` = `floor(x + 0.5)`" as an identity, which a future port could rely on.

**What taking it would involve.**
- Decide whether coordinates should follow Java 7+ exactly. Catroid converts float coordinates, so the exact Java edge is itself only approximately Android's.
- If so: replace `javaRound` with the Java 7+ algorithm already written for the formula function, pin 0.49999999999999994 and a 2⁵²-adjacent value, and re-run every golden. They should stay byte-identical, since no golden input sits on these edges.
- Either way, keep the corrected wording: ADR-012's rounding line and the `javaRound` comment now note the two edges and point here.

## US-326 — `setVariable` with a NaN formula writes 0 here and NaN in Catroid

**Found**: 2026-10-19, by `swift-architect` planning the Variables feature.
- **What ADR-018 says:** data bricks substitute 0 on a bad formula ("`setVariable` writes 0 … mirroring Catroid data actions reading through `interpretDouble`").
- **What current Catroid does:** `SetVariableAction.kt:48` reads through `interpretObject`, which is `formulaTree.interpretRecursive(scope)` with no catch (`Formula.java:186-188`). A formula evaluating to NaN (`sqrt(-1)`) is stored as NaN, not 0.
- **Why it matters from the Variables feature on:** with `=` comparing NaN equal to itself (Variables brief D1), after `set x to sqrt(-1)`, `x = 0` is 0 in Catroid and 1 here. Language tests that store an expected `"NaN"` would read 0.
- **Not taken in Variables:** it changes ADR-018's never-halt fallback and the non-finite policy of `Variable` (ADR-037 refuses non-finite at input), so it wants its own decision.

**What taking it would involve.**
- Decide whether a variable may hold NaN at runtime (the store is runtime-only, so ADR-037's persisted-value rule is not touched directly).
- If so: `setVariable`/`changeVariableBy` store the evaluated NaN; amend ADR-018's data-brick bullet; check every reader of the store (`interpretInteger` of a NaN variable, sensors, ForVariableFromTo's bounds).
- Either way, correct ADR-018's provenance sentence (ADR-032 invariant 3).
- *Update 2026-10-25 (Variables feature review):* the divergence is pinned by `StepperVariableTests.setVariableNaNIsZero`, and ADR-018's sentence is marked `[disputed: US-326]` inline. The decision itself is still open.

## US-328 — Variables follow-ups: one definition per rule

**Found**: 2026-10-25, by the feature-level `swift-code-reviewer` pass. No defect behind any of these; each is a rule spelled in more than one place.
- ADR-049's truthiness in one helper (the If's `interpretInteger != 0` is inline in `Interpreter+Step.swift`, WaitUntil's in `Interpreter+Conditions.swift`).
- The editor's indent walk (`Script.indentDepths`) and the app's nesting counts (`BrickRowPresentation.enclosingCounts`) are parallel walks that must agree.
- A `BrickKind.isBlockMarker`, which is spelled out in four places today.
- One category for `BinaryOperator` (arithmetic, comparison, logical), which is classified four times today.
- Public API trims: `Script.matchingElse`, `opensLoop`, `isLoopEnd` are used only by tests; `ParameterEditorKind.init(_ value:)` answers differently from `init(_ parameter:)` for a condition.
- Two pre-existing ADR-019 screening gaps (sub-length probes against the wrong length; the ulp figure halved), each needing one synthetic probe near a boundary.

## US-330 — The stage pixel tests read a black frame on a saturated CI runner

**Found**: 2026-10-26, Project management PR 1 (twice in one day), after one occurrence on 2026-10-24. `StageFieldRenderingTests.designIsOnTop` and `.matIsDrawnAtCurrent` failed on CI with no change near the stage, and passed on the next commit; locally they pass. The 2026-10-24 result bundle showed an all-black `ImageRenderer` pixel, the same family as US-327's main-actor saturation.
- **Options:** render off the main actor or with a retry on an all-black frame; serialise the suite (`.serialized`) so it never renders while the soak tests run; or assert on the draw plan rather than on pixels where a pixel adds nothing.
- Each occurrence costs a re-run (about 8 min) and a triage.


## US-331 — The format freeze is handed to a release checklist that does not exist

**Found**: 2026-10-28, by M5's knowledge-graph drift check (a `semantically_similar_to` edge between project management D10 and brick backend D8).
- **The commitment:** project management D10 says ADR-037's format freeze "becomes a release-checklist step, with a frozen-v1 vocabulary census test added at that step".
- **The gap:** there is no release checklist: none in the roadmap, this backlog, any ADR or `.claude/commands/`. ADR-037's 2026-10-18 amendment (Sebastian's decision of 2026-10-17) records the three admission operations (content-derived stamp, `≤ current` decode, refuse content newer than its stamp) "so the freeze cannot happen without it", but nothing triggers it.
- **Why it matters:** the freeze has to happen before the first build reaches anyone else. Missing it is silent: every test stays green, and the first vocabulary change after distribution ships under v1. An older build then reads that file as `.corrupt` instead of `.unsupportedVersion`.

**What taking it would involve.**
- A release checklist with a home. Either a section of the roadmap's TestFlight checkpoint, or a `/release` command beside `/finish`, so it runs at the moment rather than being remembered. Its first item is the freeze.
- The freeze itself, per ADR-037: the frozen-v1 vocabulary census test (every `Brick`/`Formula` case known to v1, failing to compile or fail when the vocabulary grows without a version bump), then `requiredFormatVersion` and the two decode rules once v2 exists.
- An ADR-037 amendment naming the trigger, so the rule and its trigger live in one place.

---

## Scheduled out of this file — the record, because the mechanism is the point

Entries keep their ID when they are scheduled, so existing ADR and journal references keep
resolving. What is recorded here is whether the analysis captured at discovery time survived
contact with a planning session, which is the only way to tell whether this file is worth
maintaining.

- **US-211 — DST serialization field-width chokepoint.** Specified here at discovery time on
  2026-07-31, scheduled into M3 on 2026-08-04 →
  [`milestone-3/US-211-dst-field-width-chokepoint.md`](milestone-3/US-211-dst-field-width-chokepoint.md).
  Its status line said "Candidate for M3, where the export path forces the decision this
  story needs", and that is exactly what happened: the three-way choice (clamp / throwing
  init / bound at the app layer) was resolved during M3 planning once the export path existed
  to be the caller, and two facts that only surfaced then changed the answer — ADR-007's stage
  bounds do not exist as code, and `DSTHeader.init` is a second public trapping entry point
  this file never listed. Deciding it in isolation would have picked the wrong option.

- **US-313 — Zoom and pan do not feel native: no live two-finger centroid.** Specified here on
  2026-09-02 from the US-309 device session, scheduled into M3 on 2026-09-14 and **split in
  two** at planning →
  [`milestone-3/US-313a`](milestone-3/US-313a-manipulation-as-a-package-value.md) (the headless
  manipulation value) and
  [`milestone-3/US-313b`](milestone-3/US-313b-two-fingers-reach-the-stage.md) (the recogniser
  pair, the accessibility gap, the device session). **The mechanism paid for itself twice
  over**, and in the opposite direction to US-211: this entry's analysis was not merely
  incomplete, it was **wrong in a way that would have produced a defect**. It named two
  separable causes; the second — "`startAnchor` is captured once … content drifts away from
  under the touch" — is not a defect at all, and the fix it implies (a live anchor) is off by
  `(1 − m)(c₁ − c₀)`, so building it as specified would have *introduced* the drift the entry
  wanted removed. The frozen start anchor is the correct formulation and the single-touch pan
  channel was the whole bug. The entry's central premise — that the fix "conflicts with
  ADR-028's load-bearing decision" and therefore "carries an ADR revision" — was also wrong:
  it conflicts with ADR-028's *wording*, not its substance, so the outcome is a dated
  amendment plus ADR-031, and ADR-030 §7's inherited invariant is **satisfied rather than
  traded**. The entry's own suggested mechanism (`location(in:)` per frame) is the wrong input,
  and the bridge it implies (`UIGestureRecognizerRepresentable`) is iOS 18 against an iOS 17
  floor. Nine corrections in all. **What the entry got right is what mattered**: the user's own
  words, the sequencing against rung 2, and the instruction to weigh the single-commit
  invariant at a planning session rather than in a hurry.

Also settled by M3 planning, though they were ADR-020 consequences rather than backlog
entries: the `hasValidPattern`-vs-replay export-gating divergence and the adversarial-coordinate
question are now placed in
[`milestone-3/US-308`](milestone-3/US-308-design-name-and-dst-export.md) and
[`milestone-3/US-211`](milestone-3/US-211-dst-field-width-chokepoint.md) respectively.

**Scheduled into M4 (2026-09-19): US-312, US-314 and US-315.** Three of the four entries this
file held at M3 close. Each keeps its ID and moves to
[`milestone-4/`](milestone-4/); what each one's analysis was worth at planning is recorded below,
in the same spirit as US-211's and US-313's above.

- **US-312 — thread colours do not survive export** →
  [`milestone-4/US-312`](milestone-4/US-312-thread-colours-do-not-survive-export.md). **Its own
  placement advice was overridden, and was half right.** The entry said "not taken into M3 … its
  sidecar option is better decided once M5's file handling exists to decide it against", and that
  is still correct **about the sidecar** — which is why the scheduled story explicitly builds only
  the first option (say so in the app) and defers the sidecar to M5 with a research obligation
  attached. The entry's mistake was treating its three options as one decision: the cheapest
  option needs nothing from M5 and is the half the user actually meets. Planning also found a
  reason to take it *now* that the entry could not have known, because it predates the M4 scope
  being fixed: M4 is the first milestone where the colours are the **user's own choice** rather
  than a sample author's, so the false expectation gets stronger exactly as the editor gets
  better.
- **US-314 — the stage is not frozen under the fingers** →
  [`milestone-4/US-314`](milestone-4/US-314-frozen-manipulation-baseline.md). **The entry needed
  no correction at all** — the first one in this file's history. Its reproduction, its scope
  ("a `manipulationBaseline` captured at the first channel's begin"), its rejected alternative
  (pinning `settled`, which would contradict ADR-028), and its note that every existing test
  misses this by passing the same `Self.fit` every frame all survived planning unchanged and are
  carried into the story verbatim. That is what an entry written immediately after the review
  round that found it looks like.
  **Qualified 2026-09-26 at implementation**: the scope needed two corrections after all. What
  is frozen is the *fit* (`manipulationFit`), because the zoom bounds read it as well as the
  baseline. And it is captured when the tracker is not live, not when nothing is held, because
  a view torn down without a cancel would otherwise freeze every later manipulation. See
  ADR-028's US-314 amendment.
- **US-315 — the canvas and the hoop come apart** →
  [`milestone-4/US-315`](milestone-4/US-315-keyboard-transform-transient.md). The entry's two
  refuted explanations and three failed simulator reproductions were its whole value and are
  carried over intact — they are the hour the next attempt does not spend. What planning added is
  a **position**: immediately after US-409, because the palette is a detented sheet resizing the
  stage area, i.e. the same transient class, and it may hand this story the
  simulator-reproducible instance two device sessions failed to produce. The entry could not have
  found that, because it predates M4 having a palette. Its "estimate: unknown until reproduced"
  is honoured as a **timebox** rather than converted into a number.
  **One correction, and it is the useful kind**: the entry said `StageCanvas` "argues it is safe
  because a manipulation and a fit animation cannot coexist". The code says the opposite — that
  argument is explicitly **retracted** at `StageCanvas.swift:92-104` ("is false", `swift-code-reviewer`
  Q3), and the live argument is narrower. The entry was written before that retraction landed and
  **aged against the code**; the story inherited the stale citation verbatim and the cross-vendor
  round caught it. That is a real failure mode of this file — an entry is a snapshot of the code as
  well as of the reasoning, and only the reasoning is durable.

- **US-320 — a new window opens on a name error the user did not cause** → fixed by design in
  [Project management](../features/project-management.md) (pulled in 2026-10-25, D4): every
  project always has a valid name, and a blank draft is named "Design", made unique. The entry's
  reproduction held exactly; what it could not know was that the fix would come from storage, not
  from the name field.
- **US-327 — CI app tests queue past their one-minute hang guards** → decided by Sebastian on
  2026-10-25 (raise the guards) and done as Project management's first commit: the 25 one-minute
  guards became one `.hangGuard` trait of three minutes (`HangGuard.swift`). The entry's options
  survived planning unchanged; it was a decision waiting for an owner, not an analysis.
- **US-329 — project logic lives in the app target** → taken on 2026-10-26 as its own PR (#79):
  the `Projects` package target, vended through `Samples` (ADR-042 and ADR-050 amendments). The
  entry's measurement (60–110 s per app mutant) was the case for it, and it held: package mutants
  then ran in about 2.4 s.
- **US-316 — the mid-gesture tail** → taken on 2026-10-29 as its own feature,
  [Stage 60 fps tail](../features/stage-60fps-tail.md) (PR #83). The entry's named experiment was
  built (an overlap-density fixture, live dot/thread controls, an unattended scripted-gesture
  driver), but its premise did not survive the first traced session: **A0 no longer tails**, by
  hand or by driver, on a coverage-free build (ADR-043's 2026-10-29 amendment). The experiment
  needed a tail to discriminate, so it was not run, and Sebastian decided to record the
  mid-gesture pan as met with the cause unattributed. What the entry could not know: the device
  build command it inherited produced a coverage-instrumented binary, which may be what the earlier
  captures measured. Still open from it: the pinch gesture, and the A15-class capture.

**Left in this file at M4 planning: US-316 only** — it has since left too (see its bullet above; the entry itself is in git history before PR #83).
**Added since**: US-317 (2026-09-20), US-318 (2026-09-23), US-319 and US-321–US-326 (from M4 and
the brick-backend and variables features), US-328 (2026-10-25), US-330 (2026-10-26) and US-331 (2026-10-28, M5 drift check).
US-316, US-320, US-327 and US-329 have left again (above). US-322 (raster never composited in the
default layout) was pulled into US-316's feature as its PR 2 and is still open.
