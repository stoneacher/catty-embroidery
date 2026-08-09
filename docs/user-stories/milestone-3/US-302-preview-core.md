# US-302 — Preview core: colour-resolved stitch events, display list, transform math

**Epic**: E4 Stage & preview | **Estimate**: ~5 h | **Depends on**: US-301

**Status**: Implementation complete, review complete, **not closed out** —
2026-08-09. All ten test-plan items landed and all ten acceptance criteria are
met; **489 engine tests green** (from 403), CI green, SwiftLint clean.

**Eight Codex rounds ran**: **21 findings, all valid, none rejected**. Severity
by round: Medium → High → High → High → High/Medium → High → Medium → **none**.
Round 8 was clean and ended the loop on the project's new convergence rule (a
round producing no code changes), which replaced the fixed cap partly on the
evidence of this story.

The extra rounds earned themselves. Round 6 found that round 5's "fix" had
*lowered the standard* — I wrongly concluded a `fitting` overflow was
unfixable, weakened the contract, and wrote the failure into a characterisation
test, turning a bug into a specification. Round 7 found a gap in round 6's fix.
Under the retired 5-round cap this branch would have been handed over with that
High-severity defect still latent and no clean round in its history.

Closing this story out is Sebastian's.
No manual Ink/Stitch verification is needed — the milestone requires it only at
US-301 and US-308, and this story changes no DST bytes (every golden staying
green untouched is the evidence, not the claim).

**Story**: As the app layer, I want stitches to arrive already carrying their colour and to accumulate in an append-only display list with unit-tested zoom/pan math, so the preview never re-implements engine semantics and never re-assembles the stream per frame.

This story implements ADR-021 and ADR-022. It is the milestone's load-bearing story: everything render-side depends on it, and because `StagePreview` is Foundation-only, the exit criterion "zoom/pan transform math is unit-tested" is met here under `swift test` with no simulator.

`InterpreterEvent`'s embroidery payloads are documented as **provisional** — "chosen to carry what US-206's producers will need so the enum need not be reshaped then". M3 is the first real *consumer*, so reshaping now is what that comment invited.

## Acceptance criteria
- [x] `InterpreterEvent.stitch` carries `color: ThreadColor`, supplied by a new public read-only `EmbroideryPatternManager.threadColor(for actor: ActorID) -> ThreadColor`. No new dependency edge: `InterpreterEvent` already imports `EmbroideryEngine` and already carries `ActorID`, `StagePoint` and `NeedleUpdate`, so ADR-016 is unaffected.
- [x] Reading `threadColor(for:)` before or after `addStitch` yields the same value — `addStitch` captures `let color = colorState.current` up front and only clears `pendingChange`. Asserted, because this invariant is what makes the change two lines in the producer rather than a refactor.
- [x] `.colorArmed` is unchanged and **no preview code path consumes it**. The app performs no ADR-015 reasoning: not the silent start, not the invalid-hex no-op, not clause-B black, not the `==121` tie-off.
- [x] New `StagePreview` target and product (depends on `Interpreter` + `EmbroideryEngine`), **Foundation-only** — no SwiftUI, no CoreGraphics. Transform math is `Double`-based; the app adds a small `CGAffineTransform` adapter in US-305.
- [x] `StitchDisplayList` is append-only, never reordered, with incrementally maintained `colorRuns` (a gapless partition of `stitches.indices`), `bounds`, and a `settledCount` rasterisation watermark. Appending N stitches is O(N) regardless of how many are already held — no rescan.
- [x] `StageTransform` is pure `Double` math: fit-to-content, pinch about an anchor, drag, zoom clamping, and both directions of the stage↔view mapping. **The y-flip exists in exactly one function.** Stage space is y-up and the engine applies no y-flip (ADR-007), so the flip is purely the renderer's; confining it makes a future "why is my design mirrored?" a one-line diff.
- [x] `StageGeometry` puts ADR-007's 500×500 stage into code for the first time, with a doc comment stating explicitly that it does **not** bound engine input — nothing bounds a `StagePoint` and a design can legitimately leave the stage.
- [x] `RunBatch.reducing(_:from:)` folds `[InterpreterEvent]` into stitches + last needle pose + terminal marker as a **pure function**, so US-306's batching is tested here rather than behind an actor.
- [x] `EmbroideryStream.requiresTraversal(from:to:)` is public and agrees with whether `append` actually added more than one record, proven differentially. Two shape risks, both real: ADR-020's dual trigger reads `stitches.last` for the encoded-delta half, so as a static it must use `EmbroideryPoint(converting: previous)` instead (believed equivalent in a real stream, **not proven** — hence a differential test rather than an assertion); and the predicate must reproduce **conversion plus every `canAppend` guard**, not just the two distance triggers, or it will claim traversal for moves ADR-020 rejects outright and emits nothing for.
- [x] **Display model ≠ export model, deliberately.** A test pins that the display list's colour sequence matches the assembled stream's for a single-object sample. Clause C/D re-emits and interpolation intermediates differ only in record sequence (duplicates and on-segment points, so the drawn path is identical). **Clause B differs in colour and must have its own multi-actor test**: when an actor changes on a layer, the replay emits **two** points at the previous actor's workspace position in explicit black — both unconditional, with `isFar` deciding only whether the second arms a jump. Those two records have no counterpart in the display list, so when the *incoming* actor's colour is not itself black the export carries black where the preview carries that actor's colour. (Not "black never appears in the display list": `ColorState.current` defaults to `.black`, so an actor that never set a colour emits black stitch events.) M3's samples are single-object so it is not user-visible in this milestone, but the test must exist and the difference must be asserted rather than assumed away. Catroid needed `EmbroideryExportIsolationTest` for the same separation.

## Test-first plan
1. A **two-brick** program — `setThreadColor` then a stitch-producing brick — because `setThreadColor` alone emits only `.colorArmed` and never a `.stitch`, while a lone stitch brick has no non-default colour to observe (Codex round 3 caught the one-brick version as unreachable). Assert the `.stitch` event's colour is the set colour, and that an invalid hex leaves it unchanged — proving the app inherits ADR-015 without implementing it.
2. Order-insensitivity of `threadColor(for:)` across an `addStitch` call.
3. Sample 2 from US-301: the display list's colour-run boundary lands on the same stitch index as the assembled stream's colour change.
4. `StitchDisplayList`: appends preserve order; `colorRuns` partition `stitches.indices` with no gaps or overlaps; `bounds` equals a from-scratch min/max; `markSettled` moves `liveTail` and nothing else; `reset` empties everything.
5. `StageTransform` round-trip: `stagePoint(of: viewPoint(of: p)) ≈ p` across a spread of points and scales.
6. y-flip direction: stage `(0, +250)` maps to a *smaller* view y than `(0, −250)`. Fit-to-content centres and preserves aspect for a non-square viewport.
7. Pinch about an anchor leaves the anchor's stage point fixed; clamping bounds scale at both ends; drags compose additively.
8. `requiresTraversal` differential. The oracle must compare **records added by that one call**, not the stream's total count — `(0,0) → (1,0)` already leaves more than one record and would be a false positive. Random pairs are breadth only: the difference trigger dominates them, so a predicate checking just `> 121` passes them all while being wrong at every boundary that matters. The **required explicit cases**, each of which defeats a predicate that the others do not:
   - **The rounding seam**: `previous (0.125, 0) → target (60.75, 0)` — difference distance 121, but the individually converted points are 0 and 122, so the *encoded delta* is 122. This is ADR-020's second trigger.
   - **The negative side is a genuinely different case, not a mirror.** Negating that pair gives `(-0.125, 0) → (-60.75, 0)`, whose converted points are 0 and −121 — encoded delta **121**, i.e. *not* a boundary case, because `javaRound` is `floor(x + 0.5)` and is asymmetric on negative halves (ADR-012). An earlier draft said "plus its mirror" with no axis defined, which named a case that does not test what it claimed (Codex round 2). Find and pin the actual negative-side seam rather than assuming symmetry.
   - **Over the split cap**: `(0, 0) → (60 500 000.5, 0)` exceeds ADR-020's cap and appends **no records at all**, so a `> 121` predicate reports traversal where nothing is emitted.
   - **Coarse-lattice rejection**: `2^58 → 2^58 + 64`, rejected by ADR-020's lattice guard for the same reason.
   The last two are why the AC says the predicate must reproduce conversion *plus every `canAppend` guard*, not just the distance triggers.
9. Multi-actor clause-B case: two actors on one layer, **both with non-black thread colours** (say red then green), so the assembled stream's **two** black records at the first actor's workspace position are distinguishable from anything the display list holds. Assert the count, not just presence — "some black points appear" would pass against a one-point implementation — and assert non-blackness of both actors, or the test proves only extra records and not the colour difference it claims (Codex round 2). Note the replay can also *drop* these records under ADR-020 rejection, so the inputs must be ordinary convertible coordinates.
10. `RunBatch.reducing`: concatenating the reductions of every `step()` batch equals the reduction of `run(maxTicks:)`'s events — ADR-018's structural invariant, one layer up.

## References
- `Packages/EmbroideryEngine/Sources/EmbroideryEngine/EmbroideryPatternManager.swift` — `addStitch` clauses A–E, `assembled()` (the `layerOps.keys.sorted()` replay that ADR-021 rejects for per-frame use)
- `Packages/EmbroideryEngine/Sources/Interpreter/InterpreterEvent.swift` — the "provisional payload" comments this story acts on
- `Packages/EmbroideryEngine/Sources/EmbroideryEngine/Geometry.swift` — `StagePoint`, `EmbroideryPoint(converting:)`, `stitchPointUnitFactor`
- ADR-009 (batched paths, rasterised settled prefix), ADR-015 (colour semantics the app must not duplicate), ADR-016, ADR-020 (the traversal trigger), ADR-021, ADR-022
- `Catroid/.../test/embroidery/EmbroideryExportIsolationTest.kt` — display/export separation, same concern
- `Catty/src/Catty/Embroidery/EmbroideryStream.swift:161-169` — the producer→renderer seam worth porting, with the cursor as an index rather than a second mutated array

## Outcome

**467 engine tests green, up from 403.** Four commits: two `[red]`/green pairs
(engine seam, then the `StagePreview` target), plus one test-only commit.

### What landed

| Where | What |
|---|---|
| `EmbroideryPatternManager` | `threadColor(for:)` — public, read-only, `.black` for an actor that never set one |
| `InterpreterEvent` | `.stitch` gains `color:`; its payload is no longer "provisional" |
| `Interpreter+Step` | the producer reads the resolved colour once per stitch burst |
| `EmbroideryStream` | public static `requiresTraversal(from:to:)`; `canAppend` gains a static pair form; the dual trigger extracted to `interpolationSplitCount` |
| `Sources/StagePreview/` | `PreviewStitch`, `StitchDisplayList`, `StageBox`, `StageGeometry`, `StageTransform`, `ViewPoint`/`ViewSize`, `RunBatch` — the package's fifth library product |

### Decisions taken during implementation

- **`requiresTraversal` is static, and the dual trigger is shared rather than
  duplicated.** ADR-020's decision now lives once, in
  `EmbroideryStream.interpolationSplitCount`, read by both the emitter and the
  predicate. They differ in exactly one argument: the emitter passes the real
  encoded anchor (`stitches.last?.position`), the predicate passes the converted
  `previous`. Confining the believed-but-unproven substitution to one argument at
  one call site is what makes the differential test a sharp test of *it*, rather
  than of two independently written copies of the rule.
- **The negative-side seam was derived, then confirmed by execution.** Writing
  `2·previous + 0.5 = P + f`, the seam requires `f < 0.5` on the negative side
  where the positive seam requires `f ≥ 0.5`, so the mirror of `(0.125, 0) →
  (60.75, 0)` *cannot* be one. The real pair is `(−0.25, 0) → (−60.875, 0)`:
  converted endpoints 0 and −122 (encoded delta 122) with the difference rounding
  to −121. Both it and the non-seam mirror are pinned.
- **One case was added beyond the story's list**: `2^58 → 2^58 − 64` must return
  **true**. Without it, a predicate that blanket-rejects everything at a coarse
  magnitude passes every other case in the plan.
- **`PreviewStitch` carries neither `layer` nor `actor`.** No M3 consumer needs
  them, and a stored layer would invite the layer-ordered redraw that ADR-021
  rejects `assembled()` for. Both stay purely additive later.
- **`RunBatch` is a delta, not an accumulator**, so US-306 appends each batch
  rather than replacing the list. Its terminal marker is `requestedDesignName`
  because that is the only completion fact the events carry — none of the run
  enum's three finish reasons is an event, and inventing a field for them would
  repeat the `RunState.failed` mistake the ROADMAP already corrected.
- **The `GoldenProgramOracle` change was not mechanical, and this is the one
  place where a mechanical fix would have done damage.** `streamRebuiltFromEvents`
  keeps discarding the event's colour and replaying `.colorArmed` through
  ADR-015 — it proves the events are a *sufficient* description, and reading the
  ready-made colour would bypass exactly what it proves. In the other direction,
  `replayGoldenProgram` now tracks the expected colour itself rather than asking
  the manager, so ~3000 stitch events per golden gained an independently derived
  colour dimension instead of a tautology.

### Four more display/export divergences, found in review

ADR-021 enumerated three (clause C/D re-emits, interpolation intermediates,
clause B). Codex round 2 found a fourth, reachable with a **single** actor:
**clause A workspace dedup**. `emitStitches` emits one event per `addStitch`
*call* — documented since M2 and deliberate, since the event is the trace of
what the program asked for and is what US-306's budget counts — but clause A
drops an identical consecutive command, so the export has no record where the
display list has an entry. The drawn path is unaffected (the extra entry sits on
the previous stitch's position), but an armed colour change across the dedup
moves the colour-run boundary one entry earlier.

Deliberately **not** fixed in the app: filtering it preview-side would put
ADR-012's clause A into the app layer, which is what ADR-021 exists to prevent.
Pinned by `clauseADedupIsAFourthDivergence`, and ADR-021 corrected in place.

Round 3 then found a **fifth**: **ADR-020 rejection**. `emitStitches` publishes
the event unconditionally while `assembled()` asks `canAppend` first, so an
unconvertible coordinate is *drawn but never stitched* — `placeAt(1e300, 0)`
then `stitch` leaves two display entries against one export record. The largest
of the five: the others shift a colour or duplicate a point, this one shows a
stitch the machine will not make. Pinned by `adr020RejectionIsAFifthDivergence`.

Round 4 found a **sixth** (the assembler's inter-layer boundary emits a colour
change and a jump, each re-emitting the previous layer's last point — two
export-only records) and a **seventh** (ordering: the export is layer-sorted,
the display list keeps execution order). Both pinned by test.

The enumeration was wrong three times, so ADR-021 now states the **rule** as
normative and the list as illustrative-and-incomplete: **the display list is the
trace of what the program asked for; the export model is the trace of what the
machine will do.** They coincide only for a single-object, single-layer design
with no dedup, no rejection and no interpolation — which is exactly what M3's
samples are, and why no M3 user sees a difference. The preview is a preview of
the *program*, not of the file.

### ADR-019 screening

Stated rather than measured, in the ADR-020 shape. This story's boundary inputs
sit **deliberately on** the ±121 threshold — that is the subject, not an accident
needing margin — and each is pinned by name with its arithmetic in the test's doc
comment. No new golden depends on a threshold crossing; every existing DST golden
stayed byte-identical and untouched, which is the evidence that extracting
`interpolationSplitCount` moved no emission.

### No new ADR

ADR-023…026 stay with their owner stories (US-303/305/211/308). Nothing here
needed a decision ADR-021 and ADR-022 had not already made.

### Notes for later stories

- **US-305**: the `CGAffineTransform` adapter maps `ViewPoint`/`ViewSize`;
  `requiresTraversal` is the call for drawing travel moves distinctly.
- **US-306**: `RunBatch.reducing(_:from:)` is the batching, already tested;
  `StitchDisplayList.append(contentsOf:)` is the single observable mutation.
- **A red-phase lesson worth carrying**: the first display-list stub appended
  nothing, and a test indexing the settled prefix *trapped* on an empty array
  instead of failing. A crash takes its whole parallel suite with it, so it hides
  results rather than reporting one. Red-phase stubs must be total enough that
  the tests fail rather than die.
