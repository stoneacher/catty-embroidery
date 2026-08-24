import StagePreview
import Testing

/// US-307 test item 2, the half that is **new**.
///
/// The story asks for "clamping holds at both ends", and that already ships and is green —
/// `StageTransformTests.scaleClampsAtBothEnds` has asserted both ends since US-302. Writing
/// it again would produce a test that has never been red, so what is asserted here is the
/// clamp behaviour this story actually introduces: a floor that depends on the *fit*, so an
/// out-of-hoop design can be pinched back out to show itself whole.
@Suite("Stage zoom bounds")
struct StageZoomBoundsTests {
    /// The scale a design 6402 stage points wide needs in a 288-point viewport — below the
    /// gesture minimum, and legal: `StageTransform.minimumScale`'s own documentation works
    /// this case through, and its DST extents are ±6402 units, inside the 4-wide header
    /// fields.
    private static let outOfHoopFit = StageTransform.fitting(
        StageBox(minX: -3201, minY: -20, maxX: 3201, maxY: 20),
        in: ViewSize(width: 288, height: 288)
    )

    private static let inHoopFit = StageTransform.fitting(
        StageGeometry.box, in: ViewSize(width: 390, height: 390)
    )

    /// The premise the rest of this suite rests on, asserted rather than assumed: the
    /// out-of-hoop fit really is below the gesture floor. If a later change to `fitting` or
    /// to the padding lifted it above 0.05, every test below would still pass while
    /// testing nothing.
    @Test("the out-of-hoop fixture really does fit below the gesture minimum")
    func theFixtureIsBelowTheGestureMinimum() {
        #expect(Self.outOfHoopFit.scale < StageTransform.minimumScale)
        #expect(Self.inHoopFit.scale > StageTransform.minimumScale)
    }

    @Test("an out-of-hoop fit lowers the floor to the fit itself")
    func anOutOfHoopFitLowersTheFloor() {
        let bounds = StageZoomBounds(fitting: Self.outOfHoopFit)

        #expect(bounds.minimum == Self.outOfHoopFit.scale)
        #expect(bounds.maximum == StageTransform.maximumScale)
    }

    @Test("an in-hoop fit keeps the ordinary gesture minimum")
    func anInHoopFitKeepsTheGestureMinimum() {
        let bounds = StageZoomBounds(fitting: Self.inHoopFit)

        #expect(bounds.minimum == StageTransform.minimumScale)
    }

    /// The property that makes this type safe to introduce: it only ever **widens**.
    ///
    /// Every one of `pinched`'s hardened invariants is stated against `minimumScale`, so a
    /// bound that could rise above it would silently change what those tests mean. Asserted
    /// over both fixtures plus the degenerate viewport, rather than argued.
    @Test("the bound never narrows the range a pinch could already reach")
    func theBoundOnlyEverWidens() {
        let fits = [
            Self.outOfHoopFit,
            Self.inHoopFit,
            StageTransform.fitting(StageGeometry.box, in: .zero),
            StageTransform(scale: StageTransform.maximumScale)
        ]
        for fit in fits {
            let bounds = StageZoomBounds(fitting: fit)
            #expect(bounds.minimum <= StageTransform.minimumScale)
            #expect(bounds.maximum >= StageTransform.maximumScale)
            #expect(bounds.minimum <= bounds.maximum)
        }
    }

    /// **The differential pin.** `clamping` and `StageTransform.clampedScale` are two
    /// spellings of one rule, which is where a later edit fixes one and forgets the other —
    /// the same hazard `viewRect(of:)` and `mapsFinitely` are each pinned against. Run over
    /// the hostile inputs `StageTransformFinitenessTests` uses, because the interesting
    /// agreement is at the infinities: mapping every non-finite value to the floor is the
    /// defect that turned an enormous zoom *in* into the maximum zoom *out*.
    @Test("the default bound agrees with clampedScale on every input, hostile ones included")
    func theDefaultBoundAgreesWithClampedScale() {
        let scales = [
            0.0, -0.0, 1.0, 0.05, 50.0, 1e-9, 1e9, -1.0, -1e9,
            .greatestFiniteMagnitude, -.greatestFiniteMagnitude,
            .leastNonzeroMagnitude, .infinity, -.infinity, .nan
        ] as [Double]

        for scale in scales {
            #expect(
                StageZoomBounds.gestureDefault.clamping(scale)
                    == StageTransform.clampedScale(scale),
                "disagreement at \(scale)"
            )
        }
    }

    /// NaN has no direction to preserve, so it collapses to the floor — and the floor is now
    /// design-dependent, which is the case the shared spelling above cannot cover.
    @Test("NaN collapses to this bound's own floor, not to the gesture minimum")
    func nanCollapsesToThisBoundsFloor() {
        let bounds = StageZoomBounds(fitting: Self.outOfHoopFit)

        #expect(bounds.clamping(.nan) == Self.outOfHoopFit.scale)
    }

    /// Direction-preserving at the infinities, stated for the design-dependent floor for the
    /// same reason `clampedScale` states it: both infinities must fall out of the ordinary
    /// clamp rather than through a special case.
    @Test("the infinities clamp in their own direction")
    func theInfinitiesClampInTheirOwnDirection() {
        let bounds = StageZoomBounds(fitting: Self.outOfHoopFit)

        #expect(bounds.clamping(.infinity) == bounds.maximum)
        #expect(bounds.clamping(-.infinity) == bounds.minimum)
    }

    /// The whole point of the type, at the level `pinched` is actually called: a pinch-out on
    /// an out-of-hoop design reaches its fit instead of stopping 11 % short of it.
    @Test("a bounded pinch-out reaches the fit that an absolute floor would refuse")
    func aBoundedPinchOutReachesTheFit() {
        let fit = Self.outOfHoopFit
        let zoomedIn = fit.pinched(
            by: 10, about: ViewPoint(x: 144, y: 144), within: StageZoomBounds(fitting: fit)
        )

        let backOut = zoomedIn.pinched(
            by: 1e-3, about: ViewPoint(x: 144, y: 144), within: StageZoomBounds(fitting: fit)
        )

        #expect(backOut.scale == fit.scale)
        // And the unbounded overload still stops at the gesture floor, so the two entry
        // points are genuinely different rather than one having replaced the other.
        #expect(
            zoomedIn.pinched(by: 1e-3, about: ViewPoint(x: 144, y: 144)).scale
                == StageTransform.minimumScale
        )
    }
}
