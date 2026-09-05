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

        /// The segments in this path, in ascending order.
        ///
        /// **An explicit pair since US-310, and the implicitness is what had to go.** This was
        /// `segmentStarts: [Int]` under the contract "segment `i` spans stitch `i → i + 1`",
        /// which is exactly the assumption ADR-029's rung 2 needs to break: while a gesture is
        /// live the frame re-strokes the whole design, and the way to make that affordable is
        /// to join `a → b` over a stride of stitches instead of every consecutive pair. A
        /// stride cannot be expressed in a single index.
        ///
        /// In `.entire`, `.settled` and `.live` every segment still spans one stitch interval
        /// (`to == from + 1`) — coarsening happens only in `.coarse`, and only above
        /// `liveCoarseningThreshold`. `StitchDrawPlanWindowTests` asserts that, because a stride
        /// leaking into a fine window would leave the suites that read `from` green while the
        /// thread rendered in dashes.
        public let segments: [Segment]
    }

    /// The penetration dots for one colour run: a contiguous index range, taken every
    /// `stride`-th index from its lower bound.
    ///
    /// A `Range` plus a stride, **not an array of the selected indices** — and the reason is
    /// the un-coarsened paths, not this one. At stride 1 an array would allocate one `Int` per
    /// stitch, up to 50 000 of them, in every settled bake; a fix for the live path would have
    /// become a regression for the settled path it does not touch. `Range` + stride is
    /// allocation-free at every stride, and `dottedIndices` is the way to read it. `indices`
    /// stays public because the window assertions in `StitchDrawPlanScalingTests` are about the
    /// range itself — so "read it through `dottedIndices`" is a **convention**, not something the
    /// type enforces, and a renderer that iterated `indices` would silently draw every dot again
    /// (`swift-code-reviewer` corrected an earlier version of this comment, which claimed no
    /// caller *could*).
    ///
    /// *(Before US-310 this comment said a `Range` was right because "**every** entry in the
    /// window is dotted — there is nothing to filter". That is still the rule at stride 1 and
    /// is no longer the whole truth, so it is rewritten rather than extended: ADR-029 records
    /// what stale prose sitting directly above the line a reader edits costs.)*
    ///
    /// **The stride is anchored at this run's own `lowerBound`, never globally.** A global
    /// `index % stride == 0` rule drops every dot of a run shorter than the stride, and what
    /// the user sees is a thread colour vanishing the instant a finger lands. Anchoring per run
    /// makes "every colour run keeps at least one dot" true by construction, including at run
    /// length 1.
    ///
    /// The dot rule itself is unchanged and is stated in display-list terms, because Catroid's
    /// cannot be evaluated here: Catroid skips dots on jump and colour-change points, but those
    /// are *synthetic records in the export model* and the display list has no synthetic
    /// entries. Every entry is a stitch the program requested, so every entry is eligible.
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

        /// Every `stride`-th index is dotted. `1` means all of them, which is what every window
        /// but `.coarse` produces.
        public let stride: Int

        /// The indices to draw a dot at — the only correct way to read this run.
        ///
        /// `StrideTo<Int>` rather than `[Int]`: no allocation, and it is computed rather than
        /// stored so `StitchDrawPlan` stays `Equatable` (`StrideTo` is not).
        public var dottedIndices: StrideTo<Int> {
            Swift.stride(from: indices.lowerBound, to: indices.upperBound, by: Swift.max(1, stride))
        }

        /// How many dots this run draws — `indices.count` only at stride 1.
        ///
        /// Arithmetic rather than `dottedIndices.count`, which would walk the sequence. It has no
        /// production caller today (the renderer iterates `dottedIndices` and never asks how
        /// many); it exists so a test can state a dot count without re-deriving the stride rule.
        ///
        /// **Spelled to avoid the overflow its own sibling warns about.** `(span + stride - 1) /
        /// stride` — the version written first — traps at `stride == Int.max`, which is exactly
        /// what `coarseningStride`'s doc forbids for a public entry point, and it was reachable
        /// because `planning` had accidentally become public (`swift-code-reviewer`).
        public var count: Int {
            let span = indices.count
            let stride = Swift.max(1, stride)
            return span == 0 ? 0 : (span - 1) / stride + 1
        }
    }

    /// One drawn segment: the thread between two stitches in the display list.
    ///
    /// `from` and `to` are indices into the list the plan was computed from, and `to` is
    /// **not** necessarily `from + 1` — a coarse plan joins across a stride of stitches
    /// (ADR-029 rung 2). It carries no invariant of its own beyond that, which is why it has a
    /// public initializer where `Stroke` and `DotRun` deliberately do not: those two exist to
    /// make "never empty, never `.suppressed`" unrepresentable, and a pair of indices has
    /// nothing equivalent to protect.
    ///
    /// A sibling of `Stroke` rather than nested inside it, because SwiftLint's one-level
    /// nesting limit is enforced here by `--strict` in CI.
    public struct Segment: Equatable, Sendable {
        public let from: Int
        public let to: Int

        public init(from: Int, to: Int) {
            self.from = from
            self.to = to
        }
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
