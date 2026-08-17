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
    public private(set) var state: RunState = .idle
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
    /// would bake once per frame — strictly worse than never baking at all. In
    /// chunks, the bake happens a handful of times per run.
    ///
    /// A starting value US-309 tunes, exactly like `bakingThreshold = 2000`.
    /// Measured at 1000: `octagonRosette` advances three times (settling at 3 000
    /// of 3 194) and `squareCoil` twice (2 000 of 2 976) — so both cross the
    /// baking threshold, and M3's real samples exercise the raster path that
    /// US-305 could only ship unreachable.
    public static let settleChunk = 1000

    public init() {}

    /// Begins a run: clears whatever the previous one left and moves to `.running`.
    ///
    /// Clearing here rather than trusting the caller is what stops a second play
    /// drawing on top of the first. It deliberately does **not** bump `revision`,
    /// which counts `apply(_:)` calls so that it can be compared against a batch
    /// count.
    public mutating func begin() {
        clear()
        state = .running
    }

    /// Folds one update in — the single mutation per frame.
    ///
    /// Every statement here is O(batch), never O(display): appending is amortised
    /// O(1) per stitch and the watermark arithmetic is constant. At the 50 000-stitch
    /// exit criterion anything that rescanned the list would be quadratic.
    public mutating func apply(_ update: RunUpdate) {
        display.append(contentsOf: update.batch.stitches)

        // Carried forward when the batch moved no needle, so a tick that only
        // stitches does not blank the pose.
        if let needle = update.batch.needle {
            self.needle = needle
        }

        if let termination = update.termination {
            state = .finished(termination.reason)
            exportModel = termination.exportModel
        }

        // Quantised to `settleChunk`, so the renderer's cached raster is rebuilt a
        // handful of times per run rather than once per frame. `markSettled` is
        // monotonic and clamped, so repeating the same value between chunk crossings
        // costs nothing and changes nothing — which is exactly why the raster's bake
        // key does not churn.
        display.markSettled(upTo: display.count - display.count % Self.settleChunk)

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
        state = .idle
    }

    private mutating func clear() {
        display.reset()
        needle = nil
        exportModel = nil
    }
}
