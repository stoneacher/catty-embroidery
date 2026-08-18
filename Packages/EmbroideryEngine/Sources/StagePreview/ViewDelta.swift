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
/// **It is the reset channel only, not the mid-gesture one** — an earlier version of this
/// comment claimed both (`swift-code-reviewer`). A gesture drives `.scaleEffect`/`.offset`
/// straight from SwiftUI's own `CGFloat`/`CGSize`; no `ViewDelta` is constructed while fingers
/// are down. The two do share the *modifiers*, and the mechanism that made this type necessary
/// is the same one that makes the gesture work: because the `StageTransform` is untouched
/// until a gesture ends, `CanvasStitchLayers.BakeKey` cannot churn and the raster is re-baked
/// exactly once, on commit — US-307's "re-rasterised on gesture end", true by construction
/// rather than by timing. That is a fact about the *channel*, not about this type.
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
        // Scale about the viewport's centre, then translate — the exact composition
        // `.scaleEffect(_, anchor: .center)` followed by `.offset(_)` performs, so this
        // function and the two modifiers cannot mean different things.
        let centre = viewport.center
        return ViewPoint(
            x: centre.x + (point.x - centre.x) * scale + translation.x,
            y: centre.y + (point.y - centre.y) * scale + translation.y
        )
    }
}
