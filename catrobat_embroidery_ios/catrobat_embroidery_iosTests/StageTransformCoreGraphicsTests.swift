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

private extension Double {
    func isApproximately(_ other: Double, within tolerance: Double = 1e-9) -> Bool {
        Swift.abs(self - other) <= tolerance
    }
}
