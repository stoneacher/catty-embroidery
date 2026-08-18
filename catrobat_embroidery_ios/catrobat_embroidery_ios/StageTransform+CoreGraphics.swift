import CoreGraphics
import EmbroideryEngine
import StagePreview

/// The `CGAffineTransform` adapter ADR-022 anticipated and assigned to US-305.
///
/// `StagePreview` is Foundation-only, so it ships `Double`-based mapping over its own
/// `ViewPoint`/`ViewSize` types and the CoreGraphics bridge lives here — in **one**
/// file, which is what makes the package's isolation test meaningful instead of a
/// formality.
extension StageTransform {
    /// The same mapping as `viewPoint(of:)`, as a matrix, for the cases where handing
    /// CoreGraphics one transform beats mapping points individually.
    ///
    /// **This necessarily re-spells the y-flip as `d: -scale`**, while
    /// `StageTransform.flippingY` is documented as the *only* place that flip exists.
    /// Two spellings of one rule is exactly where a later edit fixes one and forgets
    /// the other, so the equality is pinned differentially by
    /// `StageTransformCoreGraphicsTests` rather than trusted — the same discipline
    /// `mapsFinitely` follows by calling `viewPoint(of:)` instead of re-deriving it.
    ///
    /// Not used to `concatenate` the drawing context, deliberately: doing that would
    /// make stroke widths scale with the transform automatically, which sounds like a
    /// feature and is not — it makes the minimum-width floor and the constant-width
    /// traversal hairline inexpressible. `StitchDrawMetrics` owns widths.
    var affine: CGAffineTransform {
        CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: translation.x, ty: translation.y)
    }

    /// One stage point in view space, as a `CGPoint` — the per-point path-building call.
    func viewCGPoint(of stagePoint: StagePoint) -> CGPoint {
        let mapped = viewPoint(of: stagePoint)
        return CGPoint(x: mapped.x, y: mapped.y)
    }

    /// A stage-space box as a view-space rect: the hoop outline's frame.
    ///
    /// Goes through `affine` rather than mapping the corners by hand, and that is not
    /// stylistic. `CGRect.applying` returns the standardised bounding box, so the y-up →
    /// y-down inversion — which swaps *which* corner is the rect's origin — is handled
    /// once by CoreGraphics instead of by a sign this file would have to get right.
    /// It also keeps the corner-mapping test non-circular: that test checks this
    /// against `viewPoint(of:)`, which is a different path through the code.
    func viewRect(of box: StageBox) -> CGRect {
        CGRect(x: box.minX, y: box.minY, width: box.width, height: box.height).applying(affine)
    }
}

extension CGPoint {
    /// Whether this point can go into a `Path` at all.
    ///
    /// Lives beside the adapter because the adapter is what produces it: `viewCGPoint(of:)`
    /// maps whatever the display list holds, and ADR-021 divergence #5 means that can be
    /// non-finite. The renderer's batching is what makes the check load-bearing rather than
    /// cosmetic — a single NaN in a shared `Path` can cost every other segment in it.
    var isDrawable: Bool {
        x.isFinite && y.isFinite
    }
}

extension ViewSize {
    /// A measured SwiftUI size, on the way in to the package's fitting math.
    init(_ size: CGSize) {
        self.init(width: size.width, height: size.height)
    }
}

extension ViewPoint {
    /// A gesture translation, on the way in to `StageZoom.commit`.
    ///
    /// `DragGesture.Value.translation` is a `CGSize` — a displacement, not a position — and
    /// this is the whole of the conversion. It lives beside the other bridges rather than in
    /// the stage view because a `CGSize` reaching `StagePreview` is exactly what ADR-022's
    /// isolation test forbids, and because the view's job is to compose gestures, not to
    /// re-type their values.
    init(_ translation: CGSize) {
        self.init(x: translation.width, y: translation.height)
    }
}
