import EmbroideryEngine

/// The stage↔view mapping: a uniform scale plus a translation, in pure
/// `Double` arithmetic so it is testable with no simulator and no CoreGraphics
/// (ADR-022). US-305 adapts it to `CGAffineTransform`.
///
/// Uniform scale, never per-axis: a design must not be stretched to fill a
/// viewport, because a stitched design's proportions are the design.
public struct StageTransform: Hashable, Sendable {
    /// How far the user may zoom. Bounds exist so a pinch cannot reach a scale
    /// where the inverse mapping loses all precision, or where the whole design
    /// is a sub-pixel dot with no way back.
    public static let minimumScale: Double = 0.05
    public static let maximumScale: Double = 50

    /// View points per stage point.
    public private(set) var scale: Double

    /// Where stage-space origin lands in view space.
    public private(set) var translation: ViewPoint

    public init(scale: Double = 1, translation: ViewPoint = .zero) {
        self.scale = Self.clampedScale(scale)
        self.translation = translation
    }

    public static func clampedScale(_ scale: Double) -> Double {
        guard scale.isFinite else { return minimumScale }
        return Swift.min(Swift.max(scale, minimumScale), maximumScale)
    }

    /// The renderer's y-flip, and the **only** place it exists.
    ///
    /// Stage space is y-up and the engine applies no flip (ADR-007), so the
    /// flip is purely the renderer's. Confining it to one function makes a
    /// future "why is my design mirrored?" a one-line diff — and because
    /// negation is its own inverse, *both* mapping directions can share this
    /// one definition instead of each spelling a sign of its own.
    private static func flippingY(_ value: Double) -> Double {
        -value
    }

    /// Stage space → view space.
    public func viewPoint(of stagePoint: StagePoint) -> ViewPoint {
        ViewPoint(
            x: stagePoint.x * scale + translation.x,
            y: Self.flippingY(stagePoint.y) * scale + translation.y
        )
    }

    /// View space → stage space. The exact inverse of `viewPoint(of:)`, sharing
    /// its single flip rather than spelling a sign of its own.
    public func stagePoint(of viewPoint: ViewPoint) -> StagePoint {
        StagePoint(
            x: (viewPoint.x - translation.x) / scale,
            y: Self.flippingY((viewPoint.y - translation.y) / scale)
        )
    }

    /// The transform that shows all of `content`, centred, with `padding` view
    /// points of margin.
    ///
    /// One scalar scale for both axes: a stitched design's proportions are the
    /// design, so it is never stretched to fill the viewport. Total for
    /// degenerate input — a one-stitch design has zero width and height, and a
    /// viewport can be measured at zero before layout settles — by falling back
    /// to whichever axis has an extent, then to a scale of 1.
    public static func fitting(
        _ content: StageBox,
        in viewport: ViewSize,
        padding: Double = 16
    ) -> StageTransform {
        let availableWidth = Swift.max(viewport.width - 2 * padding, 0)
        let availableHeight = Swift.max(viewport.height - 2 * padding, 0)
        let horizontal = content.width > 0 ? availableWidth / content.width : Double.infinity
        let vertical = content.height > 0 ? availableHeight / content.height : Double.infinity
        let fitted = Swift.min(horizontal, vertical)
        let centre = content.center

        // The translation is `viewportCentre − centre × scale`, so the product
        // is where a finite box can still overflow to infinity: a design at
        // 1e308 fitted at any scale above 1 puts an infinity in the transform
        // and the preview shows nothing (Codex round 2 — round 1's midpoint fix
        // closed the *centre*, not this). Bounding the scale by what keeps the
        // product finite is the fix, and it costs nothing at ordinary
        // magnitudes: the ceiling only drops below `maximumScale` once the
        // centre is past ~1e307, which no hoop-sized design approaches.
        //
        // Precision, not just finiteness, is genuinely lost out there — at
        // `greatestFiniteMagnitude` the viewport offset is smaller than one ulp
        // of the coordinate, so the content centre cannot land exactly on the
        // viewport centre. That is inherent to `Double` and is not something a
        // different formula recovers; the guarantee this function makes is that
        // the transform stays *finite and usable* for every finite box.
        let centreMagnitude = Swift.max(abs(centre.x), abs(centre.y), 1)
        let scaleCeiling = .greatestFiniteMagnitude / centreMagnitude
        let bounded = Swift.min(fitted.isFinite && fitted > 0 ? fitted : 1, scaleCeiling)
        let scale = clampedScale(bounded)

        return StageTransform(
            scale: scale,
            translation: ViewPoint(
                x: viewport.width / 2 - centre.x * scale,
                y: viewport.height / 2 - flippingY(centre.y) * scale
            )
        )
    }

    /// Zooms by `factor` while keeping whatever stage point sits under `anchor`
    /// exactly there.
    ///
    /// The new translation is recomputed from the **clamped** scale, so the
    /// anchor stays pinned even when the clamp bites — a version that bailed
    /// out early at the limit would also keep the anchor fixed while silently
    /// refusing the part of the zoom that was still allowed.
    public func pinched(by factor: Double, about anchor: ViewPoint) -> StageTransform {
        let anchored = stagePoint(of: anchor)
        let zoomed = Self.clampedScale(scale * factor)
        return StageTransform(
            scale: zoomed,
            translation: ViewPoint(
                x: anchor.x - anchored.x * zoomed,
                y: anchor.y - Self.flippingY(anchored.y) * zoomed
            )
        )
    }

    /// Pans by a view-space delta. Additive, so a continuous gesture applied
    /// incrementally reaches the same place as one combined drag.
    public func dragged(by delta: ViewPoint) -> StageTransform {
        StageTransform(
            scale: scale,
            translation: ViewPoint(x: translation.x + delta.x, y: translation.y + delta.y)
        )
    }
}
