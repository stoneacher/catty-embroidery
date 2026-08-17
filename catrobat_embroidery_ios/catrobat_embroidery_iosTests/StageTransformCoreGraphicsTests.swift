@testable import catrobat_embroidery_ios
import CoreGraphics
import EmbroideryEngine
import StagePreview
import Testing

/// The `CGAffineTransform` adapter ADR-022 anticipated and assigned to US-305:
/// `StagePreview` is Foundation-only, so the package ships `viewPoint(of:)` over its
/// own `ViewPoint`/`ViewSize` types and the app bridges to CoreGraphics here.
///
/// **The point of this suite is that the bridge cannot drift from what it bridges.**
/// `affine` necessarily re-spells the y-flip as `d: -scale`, while
/// `StageTransform.flippingY` is documented as the *only* place that flip exists. Two
/// spellings of one rule is exactly the setup where a later edit fixes one and leaves
/// the other, so the equality is pinned differentially rather than trusted — the same
/// discipline `StageTransform.mapsFinitely` follows by calling `viewPoint(of:)` instead
/// of re-deriving its arithmetic.
@Suite("Stage transform CoreGraphics adapter")
struct StageTransformCoreGraphicsTests {
    /// Deliberately includes negative y (where the flip shows), asymmetric
    /// translations (where a transposed `tx`/`ty` shows) and a non-unit scale (where a
    /// missing scale shows). A single point at the origin would pass against almost
    /// any wrong matrix.
    private static let transforms = [
        StageTransform(),
        StageTransform(scale: 2, translation: ViewPoint(x: 30, y: -70)),
        StageTransform(scale: 0.25, translation: ViewPoint(x: -11.5, y: 4)),
        StageTransform.fitting(StageGeometry.box, in: ViewSize(width: 390, height: 700))
    ]

    private static let points = [
        StagePoint(x: 0, y: 0),
        StagePoint(x: 10, y: 0),
        StagePoint(x: 0, y: 10),
        StagePoint(x: -250, y: -250),
        StagePoint(x: 250, y: 250),
        StagePoint(x: -33.5, y: 77.25)
    ]

    @Test func theAffineTransformAgreesWithTheDoubleMapping() {
        for transform in Self.transforms {
            for point in Self.points {
                let throughAffine = CGPoint(x: point.x, y: point.y).applying(transform.affine)
                let throughPackage = transform.viewPoint(of: point)

                #expect(Double(throughAffine.x).isApproximately(throughPackage.x))
                #expect(
                    Double(throughAffine.y).isApproximately(throughPackage.y),
                    "the y-flip must agree with StageTransform.flippingY"
                )
            }
        }
    }

    /// A box maps to the rect spanned by its mapped corners — with the y edges
    /// **swapped**, because stage space is y-up and view space is y-down. Getting this
    /// wrong yields a rect with negative height, which `CGRect` silently standardises,
    /// so the hoop would still draw and would simply be in the wrong place.
    @Test func theStageBoxMapsToTheSameViewRectAsItsMappedCorners() {
        for transform in Self.transforms {
            let box = StageGeometry.box
            let rect = transform.viewRect(of: box)

            let topLeft = transform.viewPoint(of: StagePoint(x: box.minX, y: box.maxY))
            let bottomRight = transform.viewPoint(of: StagePoint(x: box.maxX, y: box.minY))

            #expect(Double(rect.minX).isApproximately(topLeft.x))
            #expect(Double(rect.minY).isApproximately(topLeft.y))
            #expect(Double(rect.maxX).isApproximately(bottomRight.x))
            #expect(Double(rect.maxY).isApproximately(bottomRight.y))
            #expect(rect.height > 0, "a y-flip mistake shows up as a non-positive height")
        }
    }
}

/// The non-finite policy the renderer depends on, and the extreme coordinates the
/// differential suite above omits.
///
/// Codex round 2 named both as blind spots: the adapter was only ever exercised on ordinary
/// finite points, so nothing pinned what happens when ADR-021 divergence #5 puts an infinite
/// position in the display list — and nothing stated that the renderer must skip it.
@Suite("Stage transform drawability")
struct StageTransformDrawabilityTests {
    @Test("an ordinary mapped point is drawable")
    func anOrdinaryMappedPointIsDrawable() {
        let transform = StageTransform.fitting(
            StageGeometry.box, in: ViewSize(width: 320, height: 320)
        )

        #expect(transform.viewCGPoint(of: StagePoint(x: 10, y: -20)).isDrawable)
    }

    /// The case that matters: a rejected coordinate maps to something no `Path` can hold.
    /// The renderer's guard is what stops it, and this pins the predicate that guard uses —
    /// so a future "simplification" that drops the check has something to fail.
    @Test("a non-finite stage position maps to an undrawable point")
    func aNonFiniteStagePositionIsUndrawable() {
        let transform = StageTransform.fitting(
            StageGeometry.box, in: ViewSize(width: 320, height: 320)
        )

        #expect(!transform.viewCGPoint(of: StagePoint(x: .infinity, y: 0)).isDrawable)
        #expect(!transform.viewCGPoint(of: StagePoint(x: 0, y: .nan)).isDrawable)
        #expect(!transform.viewCGPoint(of: StagePoint(x: -.infinity, y: .infinity)).isDrawable)
    }

    /// A coordinate that is finite but enormous still maps finitely, because
    /// `StageTransform.fitting` reduces the scale until the content's corners do — so it is
    /// drawable, merely far away. Worth pinning separately from the non-finite case: the two
    /// look alike and want opposite treatment.
    @Test("an extreme but finite coordinate stays drawable")
    func anExtremeButFiniteCoordinateStaysDrawable() {
        let extreme = 1e12
        let transform = StageTransform.fitting(
            StageBox(minX: -extreme, minY: -extreme, maxX: extreme, maxY: extreme),
            in: ViewSize(width: 320, height: 320)
        )

        #expect(transform.viewCGPoint(of: StagePoint(x: extreme, y: extreme)).isDrawable)
        #expect(transform.viewCGPoint(of: StagePoint(x: -extreme, y: -extreme)).isDrawable)
    }

    /// The adapter and the package mapping must agree at extremes too, not just on the
    /// ordinary points the suite above uses — the differential pin is worthless if it only
    /// covers the inputs where nothing goes wrong.
    @Test("the affine transform agrees with the double mapping at extreme coordinates")
    func theAffineAgreesAtExtremeCoordinates() {
        let transform = StageTransform(scale: 1e-6, translation: ViewPoint(x: 160, y: 160))

        for coordinate in [1e12, -1e12, 1e300, -1e300] {
            let point = StagePoint(x: coordinate, y: coordinate)
            let throughAffine = CGPoint(x: point.x, y: point.y).applying(transform.affine)
            let throughPackage = transform.viewPoint(of: point)

            #expect(Double(throughAffine.x) == throughPackage.x)
            #expect(Double(throughAffine.y) == throughPackage.y)
        }
    }
}

private extension Double {
    func isApproximately(_ other: Double, within tolerance: Double = 1e-9) -> Bool {
        Swift.abs(self - other) <= tolerance
    }
}
