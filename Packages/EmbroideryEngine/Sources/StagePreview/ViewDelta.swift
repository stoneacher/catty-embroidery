/// A view-space similarity: scale about the viewport's centre, then translate.
///
/// **This is the shape SwiftUI can animate, which is the whole reason it exists.** A
/// `StageTransform` held in `@State` is not animatable — `Canvas` re-strokes from whatever
/// transform it is handed, and there is no interpolation between two of them — so
/// `withAnimation { zoom.fitToContent() }` animates nothing at all. What *is* animatable is
/// `.scaleEffect(_:anchor:)` plus `.offset(_:)` over the already-rendered canvas, and those
/// two modifiers consume exactly a scale-about-an-anchor and a translation. So the double-tap
/// reset runs on this channel and swaps the transform at completion.
///
/// The anchor is fixed at the centre rather than being a field: the reset's endpoints are two
/// whole transforms, and any similarity between them can be written about *any* anchor by
/// absorbing the difference into the translation. One less field is one less thing for a call
/// site to get wrong.
///
/// It is also the mid-gesture channel. `.scaleEffect`/`.offset` during a pinch is ADR-009's
/// "settled stitches rasterized to a cached image once counts grow" being blitted through the
/// transform as a GPU scale — and because the *transform* is untouched until the gesture ends,
/// `CanvasStitchLayers.BakeKey` cannot churn and the raster is re-baked exactly once, on
/// commit. That makes US-307's "re-rasterised on gesture end" true by construction rather than
/// by timing.
public struct ViewDelta: Equatable, Sendable {
    /// View points per view point. Always positive: a similarity that mirrored the stage
    /// could not come from two `StageTransform`s, whose single y-flip is shared.
    public let scale: Double

    /// Applied *after* the scale, in view space.
    public let translation: ViewPoint

    /// Changes nothing — the value a settled canvas renders through, and the value the
    /// reset animation ends at.
    public static let identity = ViewDelta(scale: 1, translation: .zero)

    public init(scale: Double, translation: ViewPoint) {
        self.scale = scale
        self.translation = translation
    }

    /// Where `point` lands once this delta is applied inside `viewport`.
    ///
    /// Exists so the delta can be pinned **differentially** — against the two transforms it
    /// was derived from, rather than against a re-spelling of its own arithmetic. See
    /// `ViewDeltaTests`.
    public func apply(to point: ViewPoint, in viewport: ViewSize) -> ViewPoint {
        // Red-phase stub.
        _ = point
        _ = viewport
        return .zero
    }
}
