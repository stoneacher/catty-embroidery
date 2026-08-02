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

    // Deliberately not covered, stated rather than left silent: the split cap
    // is exercised far above and far below, never at 1,000,000 splits itself.
    // A move at the cap emits over a million stitches, which is seconds of
    // runtime and hundreds of megabytes in a suite that runs in a tenth of a
    // second — the boundary is a chosen round number rather than a semantic
    // edge like ±121, so the cost buys little (Codex US-210 round 2 named the
    // gap; this is the answer to it, not an oversight).

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

    @Test("A move the stage lattice cannot subdivide emits nothing instead of recursing forever")
    func moveTooCoarseToSubdivideIsANoOp() {
        // Codex US-210 round 1. Both endpoints convert exactly and the move is
        // only 128 units, so neither the conversion guard nor the split cap
        // fires — but at 2^58 the gap between adjacent `Double`s is 64 stage
        // points, so 128 units *is* one lattice step and there is no stage
        // coordinate in between. The midpoint 2^58 + 32 is exactly halfway
        // between neighbours and ties-to-even snaps it back onto `previous`,
        // so the split makes no progress and the target re-enters the same
        // decision unchanged: unbounded recursion, not a trap.
        //
        // The general rule this pins (ADR-020): interpolation needs a lattice
        // step of at most ±121 units, otherwise no encodable non-zero move
        // exists at these coordinates at all and the move is refused whole.
        let base = 288_230_376_151_711_744.0 // 2^58
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: base, y: 0))
        stream.addStitch(at: StagePoint(x: base + 64, y: 0)) // the next representable Double

        #expect(stream.count == 1)
        #expect(stream.lastStitchPosition == EmbroideryPoint(x: 576_460_752_303_423_488, y: 0))
    }

    @Test("Just below the coarse-lattice threshold a move still interpolates")
    func moveAtTheCoarsestSubdividableLatticeStillInterpolates() {
        // One binade down: at 2^57 the lattice step is 32 stage points = 64
        // units, comfortably inside ±121, so a two-step move subdivides into
        // two 64-unit hops. The guard refuses what cannot be subdivided, not
        // everything large.
        let base = 144_115_188_075_855_872.0 // 2^57
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: base, y: 0))
        stream.addStitch(at: StagePoint(x: base + 64, y: 0)) // two lattice steps, 128 units

        #expect(stream.count == 5)
        expectEveryDeltaEncodable(stream)
    }

    @Test("A coarse axis only blocks the move when that axis is the one being split")
    func coarseStationaryAxisDoesNotBlockAFineAxisMove() {
        // Codex US-210 round 2: the first version of the lattice guard took one
        // maximum over all four components, so a coordinate merely *sitting* at
        // a coarse magnitude vetoed a move on the other axis. Here x never
        // moves and the encoded delta is (0, 2) — directly encodable, nothing
        // to subdivide — yet it was silently dropped. The guard is per-axis and
        // applies only to an axis that actually has to be split.
        let base = 288_230_376_151_711_744.0 // 2^58, lattice step 64 stage points
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: base, y: 0))
        stream.addStitch(at: StagePoint(x: base, y: 1))

        #expect(stream.stitches.map(\.position.y) == [0, 2])
        #expect(stream.count == 2)
    }

    @Test("A long move on the fine axis still interpolates from a coarse coordinate")
    func longMoveOnTheFineAxisInterpolatesFromACoarseCoordinate() {
        // The same asymmetry one step further: y moves 200 units, so it *does*
        // need splitting — and y's lattice is fine, so it can be. x is coarse
        // but stationary and is carried along exactly (`javaRound` is the
        // identity at magnitudes whose spacing exceeds 1).
        let base = 288_230_376_151_711_744.0 // 2^58
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: base, y: 0))
        stream.addStitch(at: StagePoint(x: base, y: 100))

        #expect(stream.stitches.map(\.position.y) == [0, 0, 100, 200, 200])
        #expect(stream.stitches.allSatisfy { $0.position.x == 576_460_752_303_423_488 })
        expectEveryDeltaEncodable(stream)
    }

    @Test("A move inward across a binade boundary subdivides — the lattice there is finer")
    func inwardMoveAcrossABinadeBoundaryStillInterpolates() {
        // Codex US-210 round 3. `.ulp` at an exact power of two reports the
        // spacing going *outward*: at 2^58 it is 64, but everything just below
        // sits on a 32-point lattice. A move heading back toward zero therefore
        // has a representable midpoint (2^58 − 32) and subdivides into two
        // 64-unit hops — while the outward move of the same length has none.
        // The guard has to measure the spacing *inside* the interval, not at
        // whichever endpoint happens to be a power of two.
        let base = 288_230_376_151_711_744.0 // 2^58
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: base, y: 0))
        stream.addStitch(at: StagePoint(x: base - 64, y: 0))

        #expect(stream.stitches.map(\.position.x) == [
            576_460_752_303_423_488, // 2^59
            576_460_752_303_423_488, // interpolation: duplicate-of-previous
            576_460_752_303_423_424, // intermediate at stage 2^58 − 32
            576_460_752_303_423_360, // target as jump
            576_460_752_303_423_360 // plain target
        ])
        #expect(stream.stitches.map(\.isJump) == [false, true, true, true, false])
        expectEveryDeltaEncodable(stream)

        // The mirror, inward from the negative side.
        var mirrored = EmbroideryStream()
        mirrored.addStitch(at: StagePoint(x: -base, y: 0))
        mirrored.addStitch(at: StagePoint(x: -base + 64, y: 0))
        #expect(mirrored.count == 5)
        expectEveryDeltaEncodable(mirrored)
    }

    @Test("A move that would strand a sub-hop on the coarse lattice is still refused")
    func outwardMoveWhoseSubHopCannotProgressIsRefused() {
        // The reason the guard cannot simply take the *finer* endpoint: two
        // lattice steps outward from 2^58 subdivides once into a 128-unit hop
        // that is itself non-progressing, so admitting it would only move the
        // stack overflow one level down. Measuring the coarsest spacing inside
        // the interval refuses it up front.
        let base = 288_230_376_151_711_744.0 // 2^58
        var stream = EmbroideryStream()
        stream.addStitch(at: StagePoint(x: base, y: 0))
        stream.addStitch(at: StagePoint(x: base + 128, y: 0))

        #expect(stream.count == 1)
    }

    @Test("The coarse-lattice refusal is symmetric in sign and axis")
    func coarseLatticeRefusalIsSymmetric() {
        // The termination proof covers negative and y-driven cases, but the
        // tests pinned only positive x (Codex US-210 round 2 blind spot).
        let base = 288_230_376_151_711_744.0 // 2^58
        var negative = EmbroideryStream()
        negative.addStitch(at: StagePoint(x: -base, y: 0))
        negative.addStitch(at: StagePoint(x: -base - 64, y: 0))
        #expect(negative.count == 1)

        var yDriven = EmbroideryStream()
        yDriven.addStitch(at: StagePoint(x: 0, y: base))
        yDriven.addStitch(at: StagePoint(x: 0, y: base + 64))
        #expect(yDriven.count == 1)
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

        // The exact surviving trace, not a loose bound (Codex US-210 round 1:
        // asserting only positions and encodability let a cross-actor flag
        // migration through). Layer 0 keeps its two convertible points; every
        // clause-B emission the rejected coordinates generated is skipped
        // whole, and layer 1 — whose single op is NaN — contributes nothing,
        // so it must not leave a colour stop or a join duplicate behind.
        let stream = manager.assembled()
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 0, y: 0),
            EmbroideryPoint(x: 20, y: 0)
        ])
        #expect(stream.stitches.allSatisfy { !$0.isJump && !$0.isColorChange })
        #expect(stream.stitches.map(\.color) == [.black, .black])
        #expect(stream.colorChangeCount == 0)
        expectEveryDeltaEncodable(stream)
    }

    @Test("A rejected emission cannot hand one actor's color change to another")
    func rejectedEmissionDoesNotMigrateAColorChange() {
        // Codex US-210 round 1. The manager arms flags at *command* time and
        // the stream converts at *replay* time, so an emission the stream
        // rejects had already armed `addColorChange()` on the stream — and the
        // stream-global flag then rode the next surviving append, which in an
        // interleaved multi-actor replay belongs to a different actor. Actor
        // A's colour change landing on actor B's stitch contradicts ADR-015
        // ("the actor's next surviving stitch") and ADR-020's own claim that a
        // rejected emission preserves pending state.
        //
        // The replay now asks the stream whether an emission is acceptable
        // before arming anything, so a rejected point costs no change record.
        var manager = EmbroideryPatternManager()
        let actorA = ActorID(0)
        let actorB = ActorID(1)
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actorA)
        manager.setThreadColor(ThreadColor(red: 255, green: 0, blue: 0), for: actorA)
        manager.addStitch(at: StagePoint(x: 5e18, y: 0), layer: 0, actor: actorA) // rejected at replay
        manager.addStitch(at: StagePoint(x: 1, y: 0), layer: 0, actor: actorB)
        manager.addStitch(at: StagePoint(x: 2, y: 0), layer: 0, actor: actorA)

        let stream = manager.assembled()
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 0, y: 0),
            EmbroideryPoint(x: 2, y: 0), // clause E — actor B, and it must be flag-free
            EmbroideryPoint(x: 2, y: 0), // clause B for A's return: the change belongs here
            EmbroideryPoint(x: 2, y: 0),
            EmbroideryPoint(x: 4, y: 0)
        ])
        #expect(stream.stitches.map(\.isColorChange) == [false, false, true, false, false])
        #expect(stream.stitches.allSatisfy { !$0.isJump })
        // Only the realized change counts, so `CO = changes + 1` still holds.
        #expect(stream.colorChangeCount == 1)
    }

    @Test("An actor whose armed color change is rejected loses it — the pinned exception")
    func rejectedStitchLosesItsOwnActorsColorChange() {
        // ADR-020 accepts this rather than fixing it, so it is pinned rather
        // than left to inference (Codex US-210 round 2: the cross-actor test
        // could conceal it, because there a later clause-B change appears).
        // The manager clears the actor's pending bit at *command* time and
        // cannot know the replay will drop the point, so A's red arrives with
        // no change record at all. Under-counting is the right direction: the
        // alternative is a record attached to a stitch that does not exist.
        var manager = EmbroideryPatternManager()
        let actor = ActorID(0)
        let red = ThreadColor(red: 255, green: 0, blue: 0)
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actor)
        manager.setThreadColor(red, for: actor)
        manager.addStitch(at: StagePoint(x: 5e18, y: 0), layer: 0, actor: actor) // rejected at replay
        manager.addStitch(at: StagePoint(x: 10, y: 0), layer: 0, actor: actor)

        let stream = manager.assembled()
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 0, y: 0),
            EmbroideryPoint(x: 20, y: 0)
        ])
        #expect(stream.stitches.map(\.color) == [.black, red])
        #expect(stream.stitches.allSatisfy { !$0.isColorChange })
        #expect(stream.colorChangeCount == 0)
    }

    @Test("A manager holding only rejected points reports a pattern but assembles nothing")
    func rejectedOnlyPatternAssemblesEmpty() {
        // Characterization, not an endorsement (Codex US-210 round 2):
        // `hasValidPattern` counts *recorded* ops, which the replay may reject,
        // so the two can disagree. Nothing in the engine currently promises
        // they agree; a caller gating export on it would show an empty design
        // as exportable. Recorded in ADR-020 for whoever wires up export.
        var manager = EmbroideryPatternManager()
        let actor = ActorID(0)
        manager.addStitch(at: StagePoint(x: .infinity, y: 0), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: .nan, y: 0), layer: 0, actor: actor)

        #expect(manager.hasValidPattern)
        #expect(manager.assembled().stitches.isEmpty)
    }

    // MARK: - Helpers

    /// The clean-failure guard from `InterpolationTests`: check encodability
    /// with direct position math instead of running the production encoder, so
    /// a regression fails as an expectation rather than tripping
    /// `DSTStitchRecord`'s precondition and killing the test process.
    ///
    /// Overflow-reporting subtraction rather than plain `-`: this suite is the
    /// one that puts near-`Int`-limit positions in a stream, and two of those
    /// with opposite signs would trap the *helper* before it could report the
    /// expectation — defeating the whole point of the clean-failure pattern
    /// (Codex US-210 round 1 blind spot).
    private func expectEveryDeltaEncodable(_ stream: EmbroideryStream) {
        var previous: EmbroideryPoint?
        for stitch in stream.stitches {
            let anchor = previous ?? stitch.position
            let dx = stitch.position.x.subtractingReportingOverflow(anchor.x)
            let dy = stitch.position.y.subtractingReportingOverflow(anchor.y)
            #expect(!dx.overflow && dx.partialValue.magnitude <= UInt(DSTStitchRecord.maxDelta),
                    "unencodable dx from \(anchor.x) to \(stitch.position.x)")
            #expect(!dy.overflow && dy.partialValue.magnitude <= UInt(DSTStitchRecord.maxDelta),
                    "unencodable dy from \(anchor.y) to \(stitch.position.y)")
            previous = stitch.position
        }
    }
}
