import EmbroideryEngine

/// What to stroke, batched: ADR-009's "one `Path` per colour run" made into a value
/// the renderer merely *executes*.
///
/// **Why this is a value in `StagePreview` rather than logic inside the renderer.**
/// US-305's test plan asks that the colour-run grouping, the per-path styles and
/// member indices, and the dot rule all be asserted — and asked for it "through the
/// recording renderer double's path list". That is not possible: a double conforming
/// to `StagePreviewRenderer` records that protocol's *inputs*, and paths are produced
/// inside a renderer, so a double never has a path list. The alternatives were a
/// `GraphicsContext` spy, which the story forbids because a context in the protocol
/// would defeat ADR-009's Metal escape hatch, or a double that re-implements the
/// batching, which asserts the double. Hoisting the batching into a value makes those
/// items assertable — and puts them on the fast gate, under `swift test`, with no
/// simulator (ADR-023).
///
/// **It carries indices, never geometry**, for three separate reasons:
/// - It cannot violate ADR-021's rule that an `ArraySlice` must not be retained
///   across an append, because there is no slice to retain. ADR-021's close-out warns
///   that "US-305 would have violated it by construction"; a plan of `Int`s makes the
///   violation unrepresentable instead of merely avoided.
/// - It stays **transform-free**, so panning and zooming do not invalidate it. Only
///   appending does.
/// - Resolved geometry would mean duplicating up to 50 000 positions per frame, and a
///   per-segment struct would be Catty's node-per-stitch anti-goal one level up.
///
/// Indices refer to the `StitchDisplayList` the plan was computed from. That is a
/// contract, not a type-level guarantee: a plan outliving its list, or applied to a
/// different one, is meaningless. Plans are computed per frame and thrown away.
public struct StitchDrawPlan: Equatable, Sendable {
    /// One stroked `Path`: every segment in it shares a colour *and* a style, which
    /// is what lets it be a single `Path` at a single width.
    ///
    /// Per-run alone is **not** a valid batching unit — a run can contain short →
    /// long → short, and one stroked path cannot render the middle one hairline while
    /// the others stay normal. With three styles of which one is never drawn, the real
    /// bound is two strokes per run, so ADR-009's batching claim is untouched.
    ///
    /// **No public initializer, deliberately, and note how that is achieved.** A
    /// `public struct` gets an *internal* synthesized memberwise initializer, so simply
    /// not writing one already confines construction to this module — which makes
    /// "never empty, never `.suppressed`" an invariant of the type rather than a rule
    /// at call sites, the same chokepoint reasoning as `StageTransform.init`. An
    /// explicit `internal init` was written here first and was exactly the initializer
    /// the compiler synthesizes anyway (SwiftLint's `unneeded_synthesized_initializer`
    /// caught it). Adding `public` to an initializer here would quietly widen the
    /// chokepoint, so don't.
    public struct Stroke: Equatable, Sendable {
        public let style: StitchSegmentStyle

        /// The colour run this stroke came from.
        ///
        /// **Meaningful for `.thread` and deliberately ignored for `.traversal`.** ADR-024
        /// pins travel as *chrome* — the machine trims it, so it is not design data — and
        /// the renderer draws it in a fixed chrome colour. This field still carries the
        /// run's thread colour there because the stroke belongs to that run, which makes it
        /// an invitation to "just use the colour that's right there"; don't
        /// (`swift-code-reviewer`, US-305). Making it unrepresentable would need a second
        /// two-case style enum, rejected in planning as more surface than the invariant is
        /// worth given `Stroke` has exactly one producer.
        public let color: ThreadColor

        /// The *lower* index of each segment in this path; segment `i` spans stitch
        /// `i → i + 1`.
        public let segmentStarts: [Int]
    }

    /// The penetration dots for one colour run, as a contiguous index range.
    ///
    /// A `Range`, not an array, because **every** entry in the window is dotted —
    /// there is nothing to filter. That is the dot rule stated in display-list terms:
    /// Catroid skips dots on jump and colour-change points, but those are *synthetic
    /// records in the export model* and the display list has no synthetic entries.
    /// Every entry is a stitch the program requested, so every entry gets a dot.
    ///
    /// Deliberately "requested" and not "a real needle penetration": under ADR-020 an
    /// op can be recorded and drawn while the replay rejects it. The preview shows the
    /// requested design; that is intended, and it is a record-model difference rather
    /// than an appearance one.
    ///
    /// Constructible only inside this module, for the reason `Stroke` records.
    public struct DotRun: Equatable, Sendable {
        public let color: ThreadColor
        public let indices: Range<Int>
    }

    /// Strokes in draw order: per colour run, traversal beneath thread; runs in list
    /// order.
    public internal(set) var strokes: [Stroke] = []

    /// Dot runs in list order, drawn **after every stroke** so dots always sit on top.
    ///
    /// A deviation from Catroid, which interleaves circle and line in stitch order
    /// (`EmbroideryActor.kt:66-74`) and therefore lets a later colour run paint over an
    /// earlier run's penetration dots.
    public internal(set) var dots: [DotRun] = []
}
