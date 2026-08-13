import EmbroideryEngine
import StagePreview
import Testing

/// US-305 item 4: the hoop is drawn as an outline and is **not clipped to**, so the
/// fit target is `union(stageRect, contentBounds)` and a design that leaves the
/// hoop stays visible instead of being silently cropped.
///
/// An engine suite, not an app one: `StageBox.union`, `StageGeometry.fitTarget` and
/// `StageTransform.fitting` are all package code, so the milestone's load-bearing
/// fit behaviour is provable under `swift test` with no simulator.
@Suite("Stage fit target")
struct StageFitTargetTests {
    @Test("the fit target is the hoop alone when the design stays inside it")
    func theFitTargetIsTheHoopAloneWhenTheDesignStaysInside() {
        let inside = StageBox(minX: -100, minY: -100, maxX: 100, maxY: 100)

        #expect(StageGeometry.fitTarget(including: inside) == StageGeometry.box)
    }

    @Test("an empty display list fits the hoop alone")
    func anEmptyDisplayListFitsTheHoopAlone() {
        #expect(StageGeometry.fitTarget(including: nil) == StageGeometry.box)
        #expect(StageGeometry.fitTarget(including: StitchDisplayList().bounds) == StageGeometry.box)
    }

    @Test("a design leaving the hoop enlarges the fit target on that side only")
    func aDesignLeavingTheHoopEnlargesTheFitTarget() {
        let overflowing = StageBox(minX: -10, minY: -10, maxX: 400, maxY: 10)
        let target = StageGeometry.fitTarget(including: overflowing)

        #expect(target.maxX == 400)
        // The other three edges stay at the hoop: a union never shrinks.
        #expect(target.minX == -StageGeometry.halfExtentInPoints)
        #expect(target.minY == -StageGeometry.halfExtentInPoints)
        #expect(target.maxY == StageGeometry.halfExtentInPoints)
    }

    /// Item 4 proper: the out-of-stage extreme is *visible*, not merely included in
    /// a box. Asserted through the mapping, because that is what the user sees.
    @Test("the fitted transform keeps the out-of-hoop extreme inside the viewport")
    func theFittedTransformKeepsTheOutOfHoopExtremeInsideTheViewport() {
        let extremeX = 400.0
        let overflowing = StageBox(minX: -10, minY: -10, maxX: extremeX, maxY: 10)
        let viewport = ViewSize(width: 320, height: 320)

        let transform = StageTransform.fitting(
            StageGeometry.fitTarget(including: overflowing), in: viewport
        )
        let extreme = transform.viewPoint(of: StagePoint(x: extremeX, y: 0))

        #expect(extreme.x >= 0)
        #expect(extreme.x <= viewport.width)

        // And the hoop is still on screen — which is what the *union* buys. Fitting
        // the content alone would satisfy the two expectations above while pushing
        // the hoop's far corner off the left edge.
        let hoopCorner = transform.viewPoint(
            of: StagePoint(x: -StageGeometry.halfExtentInPoints, y: 0)
        )
        #expect(hoopCorner.x >= 0)
        #expect(hoopCorner.x <= viewport.width)
    }

    /// **ADR-021 divergence #5 reaches the fit target.** A coordinate the stream
    /// rejects is still *drawn*, so `StitchDisplayList.bounds` can carry a
    /// non-finite edge — `StageBox.center`'s own doc comment says exactly this. And
    /// `Swift.min(a, .nan)` returns `a`, so a naive union silently discards
    /// whichever operand it compares second.
    ///
    /// The rule: skip a non-finite edge **per axis**, so one bad stitch can neither
    /// delete a real extent nor shrink the target below the hoop.
    @Test("a non-finite stitch cannot shrink the fit target below the hoop")
    func aNonFiniteStitchCannotShrinkTheFitTargetBelowTheHoop() {
        let allPoisoned = StageBox(minX: .nan, minY: .nan, maxX: .nan, maxY: .nan)

        #expect(StageGeometry.fitTarget(including: allPoisoned) == StageGeometry.box)
    }

    @Test("a non-finite edge does not discard the real extent on the same axis")
    func aNonFiniteEdgeDoesNotDiscardTheRealExtentBesideIt() {
        // One stitch at a rejected coordinate, one genuinely outside the hoop.
        let mixed = StageBox(minX: .nan, minY: -10, maxX: 400, maxY: .infinity)
        let target = StageGeometry.fitTarget(including: mixed)

        #expect(target.maxX == 400, "the finite overflow must survive its poisoned sibling")
        #expect(target.minX == -StageGeometry.halfExtentInPoints)
        #expect(target.maxY == StageGeometry.halfExtentInPoints)
        #expect(target.minY == -StageGeometry.halfExtentInPoints)
    }

    /// `union` on its own terms, since `fitTarget` is only its most important
    /// caller. Commutative and never-shrinking are the two properties every other
    /// expectation here quietly relies on.
    @Test("union never shrinks either operand and does not depend on the order")
    func unionNeverShrinksAndIsCommutative() {
        let small = StageBox(minX: -5, minY: -5, maxX: 5, maxY: 5)
        let wide = StageBox(minX: 0, minY: -20, maxX: 40, maxY: 1)

        #expect(small.union(wide) == wide.union(small))
        #expect(small.union(wide) == StageBox(minX: -5, minY: -20, maxX: 40, maxY: 5))
        #expect(small.union(small) == small)
    }
}

/// The non-finite cases **as the producer can actually make them**, which the suite
/// above did not cover.
///
/// `StageFitTargetTests` hand-builds its poisoned boxes, and `expand(toInclude:)`
/// cannot produce the shape it builds: with a finite current edge a non-finite point
/// was ignored, and with a non-finite current edge a finite point was swallowed, so per
/// axis you always got *both* edges finite or *both* poisoned. The union was proven and
/// the path to it was not — and the path was where the defect lived
/// (`swift-code-reviewer`, US-305).
@Suite("Stage bounds finiteness")
struct StageBoundsFinitenessTests {
    /// The reproducer, reduced: one stitch the stream will reject, then one genuinely
    /// 750 pt outside the hoop.
    ///
    /// Reachable from a legal program — `changeXBy` accumulates without normalising, so
    /// two `greatestFiniteMagnitude` steps overflow to infinity, and ADR-021 divergence
    /// #5 means the event is still emitted and still drawn.
    private static let poisonedThenOutside = displayList([
        previewStitch(.infinity, 0, PreviewColor.red),
        previewStitch(1000, 0, PreviewColor.red)
    ])

    @Test("bounds ignore a non-finite coordinate instead of absorbing it")
    func boundsIgnoreANonFiniteCoordinate() throws {
        let bounds = try #require(Self.poisonedThenOutside.bounds)

        #expect(bounds.minX == 1000)
        #expect(bounds.maxX == 1000)
        #expect(bounds.minX.isFinite)
        #expect(bounds.maxX.isFinite)
    }

    /// The user-visible consequence, and the reason this is a defect rather than a
    /// tidiness point: with the poisoned edge absorbed, `fitTarget` collapsed back to the
    /// hoop and a stitch 750 pt outside it was fitted **off-screen** — exactly the
    /// "silently cropped" outcome the criterion and test item 4 exist to forbid. It also
    /// silenced the hoop-overflow notice, which was added so a non-sighted user learns
    /// about overflow at all.
    @Test("a rejected coordinate cannot crop the design that is genuinely outside the hoop")
    func aRejectedCoordinateCannotCropRealOverflow() {
        let target = StageGeometry.fitTarget(including: Self.poisonedThenOutside.bounds)

        #expect(target != StageGeometry.box, "the overflow must still enlarge the fit target")
        #expect(target.maxX == 1000)
    }

    @Test("a design of nothing but non-finite coordinates has no bounds at all")
    func anEntirelyNonFiniteDesignHasNoBounds() {
        let list = displayList([
            previewStitch(.infinity, .nan, PreviewColor.red),
            previewStitch(.nan, .infinity, PreviewColor.red)
        ])

        // Not "a box at infinity": there is no such thing as the bounds of nothing
        // finite, and `nil` is what `fitTarget` already handles correctly.
        #expect(list.bounds == nil)
        #expect(StageGeometry.fitTarget(including: list.bounds) == StageGeometry.box)
    }

    @Test("a non-finite coordinate on one axis does not discard the other")
    func aNonFiniteAxisDoesNotDiscardTheOther() throws {
        let list = displayList([
            previewStitch(10, 20, PreviewColor.red),
            previewStitch(.infinity, 400, PreviewColor.red)
        ])
        let bounds = try #require(list.bounds)

        #expect(bounds.maxX == 10, "the poisoned x is ignored")
        #expect(bounds.maxY == 400, "the finite y beside it still counts")
    }

    /// The incremental maintenance still agrees with the from-scratch oracle, now that
    /// both skip non-finite input — which is what stops the two drifting apart.
    @Test("incremental bounds still agree with the oracle over finite positions")
    func incrementalBoundsAgreeWithTheOracle() {
        let list = Self.poisonedThenOutside
        let finite = list.stitches.map(\.position).filter { $0.x.isFinite && $0.y.isFinite }

        #expect(list.bounds == StageBox.containing(finite))
    }
}
