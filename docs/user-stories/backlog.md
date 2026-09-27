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

## US-316 — The mid-gesture tail survives both rungs of the ladder, and the next experiment is named

**Considered at M4 planning (2026-09-19) and not taken.** It stays here, and the cost is stated
rather than glossed: M3's 60 fps exit criterion remains **unmet with no scheduled work against
it**, and the A15-class capture — open since 2026-09-02, and already re-deferred once at M3 close
on the explicit grounds that US-316 must precede it — stays blocked for a second milestone. The
risk being accepted is this file's own preamble: the ±121 trap was deferred once and then
mis-scoped twice by review. It is accepted knowingly. M4's value is the editor, and US-316 is an
open-ended measurement story whose first half is building a fixture that may refute ADR-009's bet
rather than tune it — which is not work that sits comfortably beside a milestone with a
feature-shaped exit criterion. **Whoever plans M5 should read the next two paragraphs before
deferring it a third time**, because what it would buy has already changed once (see the
2026-09-19 journal entry on re-reading an open item against what has been learned since).

**Epic**: E4 Stage & preview | **Estimate**: unknown until the fixture exists — the measurement
*is* the story | **Discovered**: 2026-09-17, US-313b's AC12/AC13 controls; carried out of M3 at
its close on 2026-09-19 as the one thing standing between the milestone and its own 60 fps exit
criterion.

**Problem**: every mid-gesture capture at 50 001 stitches still reads FAIL on the bar, and on the
tail alone — worst frame **50.008 ms** in US-310's device session and **38.076 ms** in the cleanest
capture to date (2026-09-18), against a bar of 33.3 ms. Median and p95 are both at one refresh
period, so this is a tail, not a throughput problem.

**Both standing explanations are refuted by measurement, which is what makes this a story rather
than a rung.** ADR-029's ladder has now been re-pointed twice. Rung 1 (the bake schedule) cannot
touch a path that never bakes — US-309's device session. Rung 2 (draw fewer segments) landed in
US-310, moved the median from 69.1 ms to 16.670 ms on device, and **did not move the tail at any of
four stride values**; doubling the target left the worst frame *identical* at 50.008 ms. US-313b's
two control criteria then closed the door from the other side: a 3 194-stitch design drawing *more*
uncoarsened segments than the coarsened 50 001-stitch one runs at exactly one refresh period, while
halving the coarsened count changes nothing. **The mid-gesture frame cost is not the number of
segments drawn**, and the gesture-end commit — the suspect ADR-030 named — is not it either, since
the tail is present in a capture holding a single gesture that is never released.

**The named experiment, recorded in ADR-029 as a hypothesis rather than acted on**: the two designs
differ in *area covered* far more than in geometry, so fill rate and overdraw are the candidate. A
**50 000-stitch fixture covering a small area** discriminates — if it sits at the floor, area is the
variable and the tail is a rasterisation cost rather than a planning one. This repo has no such
fixture, and building it is the story's first half.

**Open at planning, nothing decided**: whether the discriminator is a new `Samples` design or a
test-only synthetic (they answer different questions — only a sample can be captured on device with
the shipping instrument); whether a positive result implicates `Canvas` blending or the dot
ellipses specifically; and whether the answer touches **ADR-009's bet itself** rather than its
constants, which is the outcome that would matter most and the one no evidence yet supports.

**Blocks** the A15-class capture M3 carried out alongside it: confirming a fix on A15 requires
there to be a fix. Read ADR-029's 2026-09-18 amendment before taking any capture for this story — a
capsule `PASS` is not on its own sufficient evidence for the bar's dropped-frame clause.

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

**Left in this file at M4 planning: US-316 only** — see above for why, and for what it costs.
**Added since**: US-317 (2026-09-20, US-401's escalation) and US-318 (2026-09-23, found in passing during US-402).
