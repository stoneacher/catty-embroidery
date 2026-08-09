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

    /// US-302 red phase: total but deliberately wrong; the green phase maps.
    public func viewPoint(of stagePoint: StagePoint) -> ViewPoint {
        ViewPoint(x: stagePoint.x, y: stagePoint.y)
    }

    /// US-302 red phase: total but deliberately wrong; the green phase inverts.
    public func stagePoint(of viewPoint: ViewPoint) -> StagePoint {
        StagePoint(x: viewPoint.x, y: viewPoint.y)
    }

    /// US-302 red phase: total but deliberately wrong; the green phase fits.
    public static func fitting(
        _ content: StageBox,
        in viewport: ViewSize,
        padding: Double = 16
    ) -> StageTransform {
        _ = (content, viewport, padding)
        return StageTransform()
    }

    /// US-302 red phase: total but deliberately wrong; the green phase zooms.
    public func pinched(by factor: Double, about anchor: ViewPoint) -> StageTransform {
        _ = (factor, anchor)
        return self
    }

    /// US-302 red phase: total but deliberately wrong; the green phase pans.
    public func dragged(by delta: ViewPoint) -> StageTransform {
        _ = delta
        return self
    }
}
