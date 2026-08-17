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

    /// Begins a run: clears the previous one and moves to `.running`.
    public mutating func begin() {
        // Red-phase stub.
    }

    /// Folds one update in — the single mutation per frame.
    public mutating func apply(_ update: RunUpdate) {
        // Red-phase stub.
        _ = update
    }

    /// Returns to `.idle` and clears everything a run produced.
    public mutating func reset() {
        // Red-phase stub.
    }
}
