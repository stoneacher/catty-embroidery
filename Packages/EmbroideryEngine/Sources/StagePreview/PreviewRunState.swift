import EmbroideryEngine

/// Everything a running preview knows, as one pure `Sendable` value.
///
/// **This type exists so that the run's state machine is testable under
/// `swift test`.** ADR-022 keeps `StagePreview` Foundation-only, so the app's
/// `@Observable` view model cannot live here — but nothing about the *logic*
/// needs `Observation`. Hoisting all of it into a value leaves the view model
/// with one stored property and one method, and moves the transitions, the fold,
/// the export capture, the reset and the settling watermark onto the fast
/// pre-commit gate with no simulator. That is the same forced hoist that produced
/// `StitchDrawPlan` in US-305, one story later.
///
/// It also makes US-306's "exactly one observable mutation per batch" criterion
/// true **by construction** rather than by discipline: the view model has exactly
/// one observed stored property, so applying an update is necessarily one
/// mutation however many stitches it carries.
public struct PreviewRunState: Equatable, Sendable {
    /// Where the run is **and** the accessibility summary, together in one value that only
    /// a transition may write.
    ///
    /// They are bundled rather than sitting side by side because US-307 requires the summary
    /// to change only when the state does, and `private(set)` inside *this* type would not
    /// stop `apply(_:)` assigning it every frame. `RunPhase` is a separate type precisely so
    /// that `private` means something here. See its doc comment for what that proves and
    /// what it does not.
    public private(set) var phase = RunPhase()

    /// Where the run is. Forwarded, so the ~40 existing `run.state` assertions and every
    /// call site are untouched by the hoist.
    public var state: RunState {
        phase.state
    }

    /// What the stage holds, for the accessibility summary. Rebuilt on transitions only.
    public var summary: StageSummary {
        phase.summary
    }

    /// How many times the summary was rebuilt — i.e. how many state transitions there have
    /// been. Compare against `revision`, which counts batches: 2 against 139 for
    /// `octagonRosette`.
    public var summaryRevision: Int {
        phase.revision
    }

    public private(set) var display = StitchDisplayList()
    public private(set) var needle: PreviewNeedle?

    /// The export model, captured from the terminal update. `nil` until a run
    /// ends — and non-`nil` after *every* way a run can end, including a user
    /// stop, which is the criterion `RunTermination` makes structural.
    public private(set) var exportModel: EmbroideryStream?

    /// How many times `apply(_:)` has mutated this value.
    ///
    /// Not test scaffolding: it is a cache-invalidation token of exactly the kind
    /// `StitchDisplayList.resetCount` already is, and it is what makes
    /// "one mutation per batch, not per stitch" an assertable number rather than
    /// a claim about code shape. A per-stitch implementation would leave
    /// `revision` equal to the stitch count instead of the update count, and the
    /// two differ by an order of magnitude on a real sample (139 updates versus
    /// 3 194 stitches for `octagonRosette`).
    public private(set) var revision = 0

    /// How many stitches must accumulate before the watermark advances.
    ///
    /// **Quantised deliberately.** US-305's renderer re-bakes its cached raster
    /// whenever `settledCount` changes, so advancing the watermark every frame
    /// would bake once per frame — strictly worse than never baking at all.
    ///
    /// Measured at 1000: `octagonRosette` advances three times (settling at 3 000
    /// of 3 194) and `squareCoil` twice (2 000 of 2 976) — so both cross the
    /// baking threshold, and M3's real samples exercise the raster path that
    /// US-305 could only ship unreachable.
    ///
    /// **US-309 tuned the rule's *shape*, not this number, and deliberately stopped short
    /// of changing the number.** The rule is `settleWatermark(for:)`; this stays a fixed
    /// chunk, and the paragraphs below are the measurement that says why.
    ///
    /// What is known headlessly: `CanvasStitchLayers` re-bakes whenever `settledCount`
    /// changes, and a bake re-plans and re-rasterises the **whole settled prefix** — so the
    /// total work across a run is Σ chunk·k = **Θ(n²/chunk)**. At 50 000 stitches that is
    /// fifty full rasterisations, the last of them planning the entire design on a single
    /// frame near the end of every long run — a dropped frame that no capture taken *after*
    /// the design has settled could ever see. Measured in plan work alone: **26.4 ms at
    /// chunk 1 000 against 5.4 ms at chunk 5 000**, and the rasterisation those plans drive
    /// scales identically while costing far more. (Fifty is also not the "handful" an
    /// earlier version of this comment claimed; `BakeSchedulingTests` pins the real count.)
    ///
    /// The obvious fix is a chunk proportional to the count, and it was implemented and
    /// **measured to be worse**: at `chunk = count / 8` a 50 000-stitch run baked **176**
    /// times rather than fifty, because a chunk that tracks a continuously growing count
    /// moves the watermark on nearly every batch. A geometric schedule does bound the count
    /// — ~10 bakes at a ratio of 1.5 — but only by letting the live tail grow to a third of
    /// the design, i.e. stroking up to 16 000 segments *per frame* at 50 000 stitches, which
    /// is the cost ADR-009 exists to avoid. **Neither landed: do not "restore" a proportional
    /// chunk here without a device measurement that beats the fixed one** (ADR-029).
    ///
    /// So the trade is real and it is one-dimensional: **bake work falls as the chunk grows,
    /// per-frame tail work rises with it**, and the balance point is where one full
    /// rasterisation costs the same as (chunk × frames) of tail stroking.
    ///
    /// **Each side is part CPU and part GPU, and an earlier version of this comment called
    /// them both simply "GPU-bound" — which would send a reader tuning the wrong half**
    /// (Codex round 1, finding 7). The measurements above are *CPU* measurements:
    /// `StitchDrawPlan.planning` walks the colour runs and segment candidates, and
    /// `CanvasStitchLayers.stroke` builds the paths and ellipses, both synchronously on the
    /// main thread — 26.4 ms of plan work at chunk 1 000 and 0.45 ms of mid-gesture planning
    /// are main-thread milliseconds, not GPU time. The rasterisation those plans drive is the
    /// GPU half. So a regression can land on either side, and a main-thread one is the kind
    /// this engine can actually cause.
    ///
    /// What is true is that the *balance point* cannot be located headlessly: it depends on
    /// the GPU half, which no `swift test` can measure. So the fixed chunk — the tail-optimal
    /// end, and the end ADR-009's per-frame claim actually rests on — stays as shipped, and
    /// the constant is the device session's first tuning knob (ADR-029).
    ///
    /// Raising it flat is separately not an option: the shipping samples are 2 976 and
    /// 3 194 stitches, so `settleChunk = 5000` would stop both settling at all and put the
    /// cached-raster path back out of reach at runtime, undoing what US-306 achieved.
    public static let settleChunk = 1000

    /// Where the watermark sits for a list of `count` stitches.
    ///
    /// **Hoisted out of `apply(_:)` and made public and pure**, which is the part of AC5's
    /// tuning that did land: the policy can now be asserted as a function rather than only
    /// observed through a run, and a test that *restates* the rule can be told apart from one
    /// that reads it. That is not hypothetical — US-309's first bake-count test restated the
    /// old quantisation and stayed green against a mutant that changed it, because test and
    /// code computed the same wrong number from the same constant.
    public static func settleWatermark(for count: Int) -> Int {
        // `max(1, …)` guards the modulo: a zero chunk would be a division **trap** rather
        // than a degradation (`swift-code-reviewer`, US-306).
        let chunk = Swift.max(1, settleChunk)
        return count - count % chunk
    }

    public init() {}

    /// Begins a run: clears whatever the previous one left and moves to `.running`.
    ///
    /// Clearing here rather than trusting the caller is what stops a second play
    /// drawing on top of the first. It deliberately does **not** bump `revision`,
    /// which counts `apply(_:)` calls so that it can be compared against a batch
    /// count.
    public mutating func begin() {
        clear()
        phase.enter(.running, summarising: display, exportModel: exportModel)
    }

    /// The pose the stage should draw, or `nil` when no run is in flight.
    ///
    /// **A value here rather than an expression at the call site**, because the rule was an
    /// expression in `RootView` and the test that claimed to pin it recomputed the same
    /// expression in its own body — so it stayed green if the call site dropped the condition
    /// entirely (`swift-code-reviewer`). The stored `needle` is deliberately *not* cleared on
    /// finish: where the needle stopped is real information a later story may want, and only
    /// its visibility is a presentation question.
    public var visibleNeedle: PreviewNeedle? {
        state.isRunning ? needle : nil
    }

    /// Folds one update in — the single mutation per frame.
    ///
    /// **Only a running run accepts updates, and that guard is load-bearing rather than
    /// defensive.** A cancelled `AsyncStream` consumer keeps receiving elements already
    /// buffered — cancellation marks the stream terminal and does *not* discard `pending`,
    /// measured directly — so a discarded run's frames arrive after the run that replaced it
    /// has already begun. Without this, picking a new design mid-run appended the previous
    /// design's stitches to the new one, and a buffered *terminal* published the discarded
    /// design's export model, which is US-308's input (`swift-code-reviewer`).
    ///
    /// **What this guard does and does not give you**, stated precisely because an earlier
    /// version of this comment claimed it made the corruption "unrepresentable" and Codex
    /// round 1 refuted that by construction: it rejects any update arriving while the run is
    /// `.idle` or `.finished`, which covers a late frame after a `reset()` or after a natural
    /// finish. It does **not** distinguish *sessions* — `begin()` A, `reset()`, `begin()` B
    /// leaves B `.running`, so A's late frames would be accepted here. Telling one run from
    /// another needs an identity the update does not carry, so that check lives where the
    /// identity is known: `RunViewModel.generation`.
    ///
    /// Every statement here is O(batch), never O(display) *within this value*: appending is
    /// amortised O(1) per stitch and the watermark arithmetic is constant. The qualifier
    /// matters — in the app the display list is also handed into the view tree, so its buffer
    /// is not uniquely referenced and copy-on-write makes the frame O(display) regardless.
    /// ADR-024 records that cost and ADR-027 passes it to US-309; this type cannot fix it.
    public mutating func apply(_ update: RunUpdate) {
        guard state.isRunning else { return }

        display.append(contentsOf: update.batch.stitches)

        // Carried forward when the batch moved no needle, so a tick that only
        // stitches does not blank the pose.
        if let needle = update.batch.needle {
            self.needle = needle
        }

        // **After the append, and that ordering is load-bearing.** The terminal update
        // carries stitches of its own, so entering the terminal state first would summarise
        // a display list one frame short — an off-by-one nobody would see on screen and a
        // VoiceOver user would be told. Pinned by
        // `theTerminalSummaryIncludesTheTerminalBatch` rather than by this comment.
        if let termination = update.termination {
            exportModel = termination.exportModel
            phase.enter(
                .finished(termination.reason), summarising: display, exportModel: exportModel
            )
        }

        // Quantised, so the renderer's cached raster is rebuilt a bounded number of times
        // per run rather than once per frame. `markSettled` is monotonic and clamped, so
        // repeating the same value between crossings costs nothing and changes nothing —
        // which is exactly why the raster's bake key does not churn.
        //
        // The rule itself lives in `settleWatermark(for:)` rather than here, so that it can
        // be asserted as a function instead of only observed through a run. US-309 tuned the
        // rule's *shape* and deliberately left the constant alone; see `settleChunk` for the
        // Θ(n²/chunk) measurement, for why the proportional chunk measured worse, and for why
        // raising the constant flat was not an option either.
        display.markSettled(upTo: Self.settleWatermark(for: display.count))

        revision += 1
    }

    /// Returns to `.idle` and clears everything a run produced.
    ///
    /// One assignment per property and no teardown, because the interpreter is a
    /// value type and lives in the driver: there is no object graph to unpick.
    /// Contrast Catroid's three separate resets (`embroideryPatternManager.clear()`
    /// twice, `resetDrawingState()`, `resetEmbroideryThreadColor()`) and Catty's
    /// reload-from-disk.
    public mutating func reset() {
        clear()
        phase.enter(.idle, summarising: display, exportModel: exportModel)
    }

    private mutating func clear() {
        display.reset()
        needle = nil
        exportModel = nil
    }
}
