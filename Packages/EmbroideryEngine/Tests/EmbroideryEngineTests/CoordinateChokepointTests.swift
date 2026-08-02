import EmbroideryEngine
import Testing

/// US-210 / ADR-020: the engine's coordinate boundary. No caller — interpreter,
/// pattern manager, or direct stream user — can crash or hang the engine with
/// any `StagePoint`, however adversarial. Three inputs used to get through:
/// non-finite coordinates, finite ones whose ×2 conversion leaves `Int` range,
/// and pairs so far apart that interpolating between them would materialize an
/// unbounded number of jump stitches.
///
/// The guards take the ADR-014 shape rather than clamping: a rejected stitch
/// emits nothing and leaves every piece of stream state — armed flags and the
/// last stage position included — exactly as it was. Clamping would put the
/// needle somewhere the program never asked for and keep it there.
///
/// ADR-019 screening: the guard tests here clear every threshold they compare
/// against by many orders of magnitude, by construction — a coordinate is
/// either representable or 5e18. The one exception is
/// `longButSplittableMoveStillInterpolates`, whose 999 hops alternate 122 and
/// 120 units and so land *on* the ±121 boundary 500 times over; its stitch
/// count is therefore decided by which side of a `.5` tie each intermediate
/// rounds to. That is deliberate — it is the coverage that makes the
/// interpolation recursion visible — and the count is derived in the test
/// rather than observed. The ±121 semantics themselves are pinned in
/// `InterpolationTests`, also deliberately on the boundary.
@Suite("Coordinate chokepoint: non-finite, overflow, and unsplittable moves (ADR-020)")
struct CoordinateChokepointTests {
    /// The largest stage magnitude whose ×2 conversion still fits `Int`, used
    /// as the "legal but enormous" probe. Beyond it `EmbroideryPoint` refuses.
    private let nearConversionLimit = 4.6e18

    // MARK: - The stream seam

    @Test("A non-finite stitch emits nothing and leaves the stream usable")
    func nonFiniteStitchIsANoOp() {
        // `EmbroideryStream.addStitch(at: StagePoint(x: .infinity, y: 0))`
        // trapped at the ×2 conversion before ADR-020 (Codex M2-planning round
        // 2, 2026-07-16). The pattern-layer ADR-014 guards never covered it:
        // they protect the pattern path, and this is the public engine API.
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: .infinity, y: 0))
        stream.addStitch(at: StagePoint(x: 0, y: -.infinity))
        stream.addStitch(at: StagePoint(x: .nan, y: .nan))
        #expect(stream.stitches.isEmpty)

        // The stream survives the rejected stitches untouched.
        stream.addStitch(at: StagePoint(x: 10, y: 10))
        #expect(stream.stitches.map(\.position) == [EmbroideryPoint(x: 20, y: 20)])
    }

    @Test("A stitch past the ×2 conversion range emits nothing and leaves the stream usable")
    func unrepresentableStitchIsANoOp() {
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 5e18, y: 0))
        stream.addStitch(at: StagePoint(x: 0, y: -5e18))
        #expect(stream.stitches.isEmpty)

        stream.addStitch(at: StagePoint(x: -10, y: 10))
        #expect(stream.stitches.map(\.position) == [EmbroideryPoint(x: -20, y: 20)])
    }

    @Test("A rejected stitch leaves an armed jump and an armed color change pending")
    func rejectedStitchLeavesFlagsArmed() {
        // The same contract dedup already has ("A dropped duplicate leaves a
        // pending jump armed for the next stitch", `EmbroideryStreamTests`):
        // the guard returns above the flag reads, so the flags ride the next
        // stitch that actually survives rather than being swallowed.
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addJump()
        stream.addStitch(at: StagePoint(x: .nan, y: 0))
        stream.addStitch(at: StagePoint(x: 1, y: 0))
        #expect(stream.stitches.map(\.isJump) == [false, true])

        stream.addColorChange()
        stream.addStitch(at: StagePoint(x: 5e18, y: 0))
        stream.addStitch(at: StagePoint(x: 2, y: 0))
        #expect(stream.stitches.map(\.isColorChange) == [false, false, true])
        #expect(stream.colorChangeCount == 1)
    }

    @Test("A rejected stitch does not become the position later moves are measured from")
    func rejectedStitchDoesNotMoveTheAnchor() {
        // "Leave state untouched" has teeth here: if the dropped point became
        // `lastStagePosition`, the *next* stitch would measure its move from a
        // coordinate that was never stitched.
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addStitch(at: StagePoint(x: .infinity, y: .infinity))
        stream.addStitch(at: StagePoint(x: 100, y: 0))

        // Measured from the origin, so this is an ordinary 200-unit long move:
        // splitCount = ceil(200/121) = 2.
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 0, y: 0),
            EmbroideryPoint(x: 0, y: 0),
            EmbroideryPoint(x: 100, y: 0),
            EmbroideryPoint(x: 200, y: 0),
            EmbroideryPoint(x: 200, y: 0)
        ])
    }

    // MARK: - Moves too long to interpolate

    @Test("A move too long to interpolate emits nothing instead of materializing the splits")
    func unsplittableMoveIsANoOp() {
        // Both endpoints convert fine; the *move* is the problem. At this
        // separation splitCount is ~7.6e16, and the interpolation loop would
        // append jump stitches until the process ran out of memory — a hang is
        // no better than the trap this story closes. Same policy and the same
        // 1,000,000 bound as ADR-014's `maxStitchesPerUpdate`.
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: nearConversionLimit, y: 0))
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        #expect(stream.stitches.map(\.position)
            == [EmbroideryPoint(x: 9_200_000_000_000_000_000, y: 0)])

        // And the opposite-sign case, where the stage difference itself leaves
        // `Int` range before it can be compared against anything.
        var mirrored = EmbroideryStream()
        mirrored.addStitch(at: StagePoint(x: -nearConversionLimit, y: 0))
        mirrored.addStitch(at: StagePoint(x: nearConversionLimit, y: 0))
        #expect(mirrored.count == 1)
    }

    @Test("A single enormous but representable stitch still lands")
    func enormousSingleStitchStillStitches() {
        // The guard rejects what cannot be encoded or split, not what is merely
        // large: with no previous position there is nothing to interpolate.
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: nearConversionLimit, y: -nearConversionLimit))
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 9_200_000_000_000_000_000, y: -9_200_000_000_000_000_000)
        ])
    }

    @Test("A long move far beyond any real design still interpolates, re-splitting as it goes")
    func longButSplittableMoveStillInterpolates() {
        // 121,000 units is 12.1 metres — three orders of magnitude past the
        // 500-point stage and still a thousandth of the cap.
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: 0, y: 0))
        stream.addStitch(at: StagePoint(x: 60500, y: 0))

        // splitCount = ceil(121000/121) = 1000, but the emission is not 1000
        // evenly spaced points. Intermediate k sits at stage round(60.5k),
        // which is exactly 60.5k for even k and half a unit higher for odd k,
        // so the hops alternate 122 and 120 units — and every 122-unit hop
        // re-enters the guard and splits again. That recursion is what makes
        // ADR-020's backstop terminating rather than merely one-shot, and the
        // count is where it is visible: 500 odd hops cost 3 extra stitches
        // each, giving 1 first + 1 dup + (999 + 1500) loop + 1 target jump +
        // 1 plain target.
        #expect(stream.count == 2503)
        #expect(stream.lastStitchPosition == EmbroideryPoint(x: 121_000, y: 0))
        expectEveryDeltaEncodable(stream)
    }

    // MARK: - The pattern manager seam

    @Test("Adversarial coordinates through the manager leave an assemblable pattern")
    func managerToleratesAdversarialCoordinates() {
        // Two seams, not one: the manager stores stage-space ops and converts
        // positions only in the `assembled()` replay, but its clause distance
        // (`getMaxDistanceBetweenPoints`, clauses B/C/D) converts a stage
        // *difference* at command time — so a second command reaches a
        // conversion before assembly ever runs.
        var manager = EmbroideryPatternManager()
        let actor = ActorID(0)
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: .infinity, y: 0), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: .nan, y: .nan), layer: 1, actor: actor)
        manager.addStitch(at: StagePoint(x: 5e18, y: 5e18), layer: 0, actor: ActorID(1))
        manager.addStitch(at: StagePoint(x: 10, y: 0), layer: 0, actor: actor)

        let stream = manager.assembled()
        #expect(stream.stitches.allSatisfy { $0.position.x.magnitude < 1000 })
        #expect(stream.lastStitchPosition == EmbroideryPoint(x: 20, y: 0))
        expectEveryDeltaEncodable(stream)
    }

    // MARK: - Helpers

    /// The clean-failure guard from `InterpolationTests`: check encodability
    /// with direct position math instead of running the production encoder, so
    /// a regression fails as an expectation rather than tripping
    /// `DSTStitchRecord`'s precondition and killing the test process.
    private func expectEveryDeltaEncodable(_ stream: EmbroideryStream) {
        var previous: EmbroideryPoint?
        for stitch in stream.stitches {
            let dx = stitch.position.x - (previous ?? stitch.position).x
            let dy = stitch.position.y - (previous ?? stitch.position).y
            #expect(abs(dx) <= DSTStitchRecord.maxDelta, "unencodable dx \(dx)")
            #expect(abs(dy) <= DSTStitchRecord.maxDelta, "unencodable dy \(dy)")
            previous = stitch.position
        }
    }
}
