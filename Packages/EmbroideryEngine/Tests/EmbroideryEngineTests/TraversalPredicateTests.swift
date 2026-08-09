import EmbroideryEngine
import Testing

/// `EmbroideryStream.requiresTraversal(from:to:)` — the public predicate the
/// M3 renderer asks instead of re-deriving ADR-020, so a machine's travel move
/// can be drawn distinctly from thread.
///
/// **The oracle is differential, and it counts records added by *one* append.**
/// Not the stream's total count: `(0,0) → (1,0)` already leaves two records in
/// the stream (one per call) and would be a false positive. Not a
/// re-implementation of the rule either — that would only prove the predicate
/// equals itself.
///
/// **Random pairs are breadth, not evidence.** The difference trigger dominates
/// a uniform sample, so a predicate testing nothing but `> 121` passes every
/// random pair while being wrong at every boundary that matters. The explicit
/// cases below are the test; each defeats a wrong predicate the others do not.
@Suite("Traversal predicate")
struct TraversalPredicateTests {
    // MARK: - Oracles

    /// Records added by the second `addStitch` alone. `addStitch` is the public
    /// seam and differs from the internal `append` only by a dedup that fires
    /// when the two points are equal — excluded by construction, and asserted.
    private func recordsAddedByStream(from previous: StagePoint, to target: StagePoint) -> Int {
        #expect(previous != target, "the dedup seam must not be what is being measured")
        var stream = EmbroideryStream()
        stream.addStitch(at: previous, color: .black)
        let before = stream.count
        stream.addStitch(at: target, color: .black)
        return stream.count - before
    }

    /// The same question asked through the pattern manager's replay — one actor
    /// on one layer, so clauses A–D are all inapplicable and `assembled()` is
    /// literally `append(previous); append(target)`. This is the path US-305
    /// actually consumes, and it reaches `append` through 100% public API.
    private func recordsAddedByReplay(from previous: StagePoint, to target: StagePoint) -> Int {
        var manager = EmbroideryPatternManager()
        let actor = ActorID(0)
        manager.addStitch(at: previous, layer: 0, actor: actor)
        let before = manager.assembled().count
        manager.addStitch(at: target, layer: 0, actor: actor)
        return manager.assembled().count - before
    }

    private func expectAgreement(
        from previous: StagePoint,
        to target: StagePoint,
        _ comment: Comment,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let predicate = EmbroideryStream.requiresTraversal(from: previous, to: target)
        let byStream = recordsAddedByStream(from: previous, to: target) > 1
        let byReplay = recordsAddedByReplay(from: previous, to: target) > 1
        #expect(predicate == byStream, comment, sourceLocation: sourceLocation)
        #expect(predicate == byReplay, comment, sourceLocation: sourceLocation)
    }

    // MARK: - The rounding seams

    /// ADR-020's second trigger. The stage *difference* rounds to 121 — not over
    /// the threshold — but the individually converted points are 0 and 122, so
    /// the delta `DSTFile` will encode is 122 and the move must be split. A
    /// predicate reading only the difference reports `false` here and the
    /// renderer would draw sewn thread across a travel move.
    @Test("the positive rounding seam: difference 121, encoded delta 122")
    func positiveRoundingSeamRequiresTraversal() {
        let previous = StagePoint(x: 0.125, y: 0)
        let target = StagePoint(x: 60.75, y: 0)
        #expect(EmbroideryStream.requiresTraversal(from: previous, to: target))
        expectAgreement(from: previous, to: target, "the ADR-020 encoded-delta seam")
    }

    /// **The negative side is a genuinely different case, not a mirror**, and
    /// this pair was derived rather than obtained by negating the positive one.
    ///
    /// `javaRound(v) = floor(v + 0.5)`. Write `2·previous + 0.5 = P + f` with
    /// `f ∈ [0,1)`. The seam needs the difference to round to 121 while the
    /// converted endpoints differ by 122, and that pair of conditions can only
    /// hold with `f < 0.5` on the negative side, where the positive seam needs
    /// `f ≥ 0.5` (at `previous = 0.125`, `f = 0.75`). So the negation of the
    /// positive seam cannot itself be a seam — see the test below, which pins
    /// that it is not.
    ///
    /// Here `previous = −0.25` gives `f = 0`: converted `javaRound(−0.5) = 0`
    /// and `javaRound(−121.75) = −122`, encoded delta 122; the difference
    /// `javaRound(−121.25) = −121`, magnitude 121.
    @Test("the negative rounding seam, derived rather than mirrored")
    func negativeRoundingSeamRequiresTraversal() {
        let previous = StagePoint(x: -0.25, y: 0)
        let target = StagePoint(x: -60.875, y: 0)
        #expect(EmbroideryStream.requiresTraversal(from: previous, to: target))
        expectAgreement(from: previous, to: target, "the derived negative-side seam")
    }

    /// The naive mirror of the positive seam, pinned as **not** a boundary case.
    /// Converted endpoints are 0 and −121, so the encoded delta is 121 and
    /// nothing triggers. Kept as a test because an earlier draft of this story
    /// named it as "the mirror" and would have asserted the opposite.
    @Test("negating the positive seam does not give a seam")
    func negatedPositiveSeamIsNotASeam() {
        let previous = StagePoint(x: -0.125, y: 0)
        let target = StagePoint(x: -60.75, y: 0)
        #expect(!EmbroideryStream.requiresTraversal(from: previous, to: target))
        expectAgreement(from: previous, to: target, "the mirror that is not a seam")
    }

    // MARK: - Moves the engine refuses outright

    /// Past ADR-020's 1,000,000-split cap the engine appends **nothing at all**,
    /// so a `> 121` predicate would claim a traversal for a move that emits no
    /// records — a drawn travel line to a place the machine never goes.
    @Test("a move over the split cap emits nothing and so requires no traversal")
    func overTheSplitCapRequiresNoTraversal() {
        let previous = StagePoint(x: 0, y: 0)
        let target = StagePoint(x: 60_500_000.5, y: 0)
        #expect(recordsAddedByStream(from: previous, to: target) == 0)
        #expect(!EmbroideryStream.requiresTraversal(from: previous, to: target))
        expectAgreement(from: previous, to: target, "ADR-020's split cap")
    }

    /// Rejected by ADR-020's per-axis lattice guard: above ~2^58 the gap between
    /// adjacent `Double`s exceeds ±121 units, so no encodable non-zero move
    /// exists on that axis and the move is refused whole.
    @Test("a move across a lattice too coarse to subdivide emits nothing")
    func coarseLatticeRequiresNoTraversal() {
        let previous = StagePoint(x: 0x1p58, y: 0)
        let target = StagePoint(x: 0x1p58 + 64, y: 0)
        #expect(recordsAddedByStream(from: previous, to: target) == 0)
        #expect(!EmbroideryStream.requiresTraversal(from: previous, to: target))
        expectAgreement(from: previous, to: target, "ADR-020's lattice guard")
    }

    /// The case that defeats a predicate blanket-rejecting everything at a
    /// coarse magnitude — which the story's own list does not catch. Heading
    /// *down* from 2^58 enters the finer binade, has a representable midpoint,
    /// and subdivides (ADR-020's `.nextDown.ulp` reasoning).
    @Test("the same magnitude heading the other way still interpolates")
    func coarseLatticeDownwardStillRequiresTraversal() {
        let previous = StagePoint(x: 0x1p58, y: 0)
        let target = StagePoint(x: 0x1p58 - 64, y: 0)
        #expect(EmbroideryStream.requiresTraversal(from: previous, to: target))
        expectAgreement(from: previous, to: target, "the subdividable side of the lattice")
    }

    @Test(
        "a non-finite or unconvertible endpoint requires no traversal",
        arguments: [Double.infinity, -.infinity, .nan, 1e300]
    )
    func unconvertibleEndpointRequiresNoTraversal(_ value: Double) {
        let previous = StagePoint(x: 0, y: 0)
        let target = StagePoint(x: value, y: 0)
        #expect(!EmbroideryStream.requiresTraversal(from: previous, to: target))
        #expect(recordsAddedByStream(from: previous, to: target) == 0)
    }

    // MARK: - Ordinary moves

    @Test("a short move needs no traversal")
    func shortMoveRequiresNoTraversal() {
        let previous = StagePoint(x: 0, y: 0)
        let target = StagePoint(x: 1, y: 0)
        #expect(!EmbroideryStream.requiresTraversal(from: previous, to: target))
        expectAgreement(from: previous, to: target, "an ordinary short move")
    }

    @Test("a plainly long move needs a traversal")
    func longMoveRequiresTraversal() {
        let previous = StagePoint(x: 0, y: 0)
        let target = StagePoint(x: 100, y: 0)
        #expect(EmbroideryStream.requiresTraversal(from: previous, to: target))
        expectAgreement(from: previous, to: target, "the plain difference trigger")
    }

    /// Breadth only, and deliberately sampled on the ⅛ lattice near the ±121
    /// boundary so the seam region is actually visited — a uniform sample is
    /// dominated by the difference trigger. Seeded, never `SystemRandom…`:
    /// tests run in parallel and an irreproducible fixture is not a fixture.
    @Test("the predicate agrees with the engine across seeded pairs near the boundary")
    func agreesAcrossSeededPairs() {
        var generator = SplitMix64(seed: 0x5AFE_D00D)
        for _ in 0 ..< 400 {
            let previous = StagePoint(x: generator.eighthLatticeValue(), y: generator.eighthLatticeValue())
            let target = StagePoint(x: generator.eighthLatticeValue(), y: generator.eighthLatticeValue())
            guard previous != target else { continue }
            expectAgreement(from: previous, to: target, "seeded pair \(previous) → \(target)")
        }
    }
}

/// Deterministic generator for the breadth sample above.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    /// A stage value on the ⅛ lattice within ±70 — wide enough that the ±60.5
    /// half-unit seam region is sampled on both sides of zero.
    mutating func eighthLatticeValue() -> Double {
        let steps = Int(next() % 1121) - 560
        return Double(steps) / 8
    }
}
