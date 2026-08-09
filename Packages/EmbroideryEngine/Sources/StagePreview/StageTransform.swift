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

    /// **The chokepoint.** Every `StageTransform` that exists has a finite
    /// scale within the zoom bounds and a finite translation — enforced here,
    /// at the one place a value of this type can be made, rather than argued
    /// about at each call site.
    ///
    /// That this is a chokepoint rather than a bound is the lesson of four
    /// review rounds. Each earlier attempt fixed the *expression* that had
    /// overflowed and left a sibling: the midpoint but not the product, the
    /// product but not the ceiling's rounding, the ceiling but not `pinched`,
    /// `pinched`'s product but not its subtraction, and none of them the
    /// viewport. Checking intermediate terms is a losing game because there is
    /// always one more term; checking the constructed value is not, because
    /// there is only one constructor. Same shape as ADR-020 in the engine —
    /// make the bad state unrepresentable at the type level.
    ///
    /// A non-finite translation collapses to zero rather than trapping: the
    /// preview is a view, and a design placed beyond what the transform can
    /// express should be off-screen, not a crash.
    public init(scale: Double = 1, translation: ViewPoint = .zero) {
        self.scale = Self.clampedScale(scale)
        self.translation = ViewPoint(
            x: translation.x.isFinite ? translation.x : 0,
            y: translation.y.isFinite ? translation.y : 0
        )
    }

    /// Clamps into the zoom bounds. **Direction-preserving at the infinities**,
    /// which the first version was not: it mapped every non-finite value to
    /// `minimumScale`, so `pinched(by: .greatestFiniteMagnitude)` — whose
    /// `scale × factor` overflows to `+∞` — turned an enormous zoom *in* into
    /// the maximum zoom *out* (Codex round 5). Wrong-but-finite and plainly
    /// visible, which makes it worse than the overflows the earlier rounds
    /// chased.
    ///
    /// Only NaN has no direction to preserve. Both infinities fall out of the
    /// ordinary clamp correctly, so there is no special case left to get wrong.
    public static func clampedScale(_ scale: Double) -> Double {
        guard !scale.isNaN else { return minimumScale }
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

        // Reduce the scale until the content's own extent maps finitely, which
        // is what makes a hoop-sized or even wildly-oversized design usable.
        //
        // Established by checking rather than by a bound, because reasoning
        // about this product has been wrong twice: once by fixing only the
        // midpoint, once by a `greatestFiniteMagnitude / |centre|` ceiling that
        // rounds *up* and overflowed anyway. Halving from at most
        // `maximumScale` reaches `minimumScale` in about ten steps, and
        // `minimumScale` always succeeds, so the loop terminates.
        //
        // **It does not make every corner finite, and no implementation
        // could.** Content spanning most of the `Double` range needs a scale
        // below `minimumScale` to fit at all, and even at a legal scale the
        // centring translation can itself sit near `greatestFiniteMagnitude`,
        // so `point × scale + translation` overflows for a far corner (Codex
        // round 5: `minX = -greatestFiniteMagnitude`, `maxX = 1e300` in a
        // `greatestFiniteMagnitude`-wide viewport). An earlier version of this
        // comment promised all corners finite — that promise was simply false,
        // and the honest fix was to the claim rather than to the code.
        //
        // What holds: the returned transform's own fields are always finite
        // (guaranteed at `init`), and any content within a sane fraction of the
        // `Double` range maps finitely. A design at 1e308 is not a design.
        let extent = Swift.max(
            abs(content.minX), abs(content.maxX), abs(content.minY), abs(content.maxY), 1
        )
        var scale = clampedScale(fitted.isFinite && fitted > 0 ? fitted : 1)
        while scale > minimumScale, !(extent * scale).isFinite {
            scale = Swift.max(minimumScale, scale / 2)
        }

        return StageTransform(
            scale: scale,
            translation: ViewPoint(
                x: centringOffset(viewport.width / 2, centre.x, scale),
                y: centringOffset(viewport.height / 2, flippingY(centre.y), scale)
            )
        )
    }

    /// One axis of `fitting`'s translation: `viewportCentre − coordinate ×
    /// scale`, with the product **checked** rather than reasoned about.
    ///
    /// This is where a finite box could still put an infinity in the transform.
    /// Two earlier attempts each closed a case and left another: halving before
    /// summing fixed `StageBox.center` but not this product (Codex round 2),
    /// and bounding the scale by `greatestFiniteMagnitude / |centre|` failed
    /// because that division *rounds up* — at `0x7feaaa695c4b773d` the ceiling
    /// comes back as 1.2000448438435127 and the product overflows anyway
    /// (Codex round 3, by brute-force search).
    ///
    /// So the guarantee is no longer an argument about floating-point bounds;
    /// it is a branch. If the product is not finite the design is further from
    /// the origin than any scale can centre, and anchoring at the origin is the
    /// honest degradation — the transform stays usable and the design is simply
    /// off-screen, which it would be at that distance regardless.
    ///
    /// Precision is separately and unavoidably lost out there: near
    /// `greatestFiniteMagnitude` the viewport offset is below one ulp of the
    /// coordinate, so exact centring is unrepresentable in `Double` and no
    /// formula recovers it. What this function guarantees is **finite**.
    private static func centringOffset(
        _ viewportCentre: Double,
        _ coordinate: Double,
        _ scale: Double
    ) -> Double {
        // The **result**, not the product. Round 3 checked `coordinate * scale`
        // and round 4 found that `viewportCentre − scaled` overflows on its own
        // once the viewport is itself enormous. Checking terms one at a time is
        // how this defect kept surviving its own fix.
        let offset = viewportCentre - coordinate * scale
        guard offset.isFinite else { return viewportCentre.isFinite ? viewportCentre : 0 }
        return offset
    }

    /// Zooms by `factor` while keeping whatever stage point sits under `anchor`
    /// exactly there.
    ///
    /// The new translation is recomputed from the **clamped** scale, so the
    /// anchor stays pinned even when the clamp bites — a version that bailed
    /// out early at the limit would also keep the anchor fixed while silently
    /// refusing the part of the zoom that was still allowed.
    ///
    /// A zoom that cannot be represented is **refused**: returning `self`
    /// leaves a usable transform, where returning a collapsed one would jump
    /// the design somewhere the user did not ask for.
    ///
    /// The guard is on the **computed translation**, not on the intermediate
    /// product. Round 3 checked `anchored × zoomed` and round 4 found that
    /// `anchor − product` overflows on its own when both are large and of
    /// opposite sign. There is always one more intermediate term; there is only
    /// one result.
    public func pinched(by factor: Double, about anchor: ViewPoint) -> StageTransform {
        let anchored = stagePoint(of: anchor)
        let zoomed = Self.clampedScale(scale * factor)
        let translated = ViewPoint(
            x: anchor.x - anchored.x * zoomed,
            y: anchor.y - Self.flippingY(anchored.y) * zoomed
        )
        guard translated.x.isFinite, translated.y.isFinite else { return self }
        return StageTransform(scale: zoomed, translation: translated)
    }

    /// Pans by a view-space delta. Additive, so a continuous gesture applied
    /// incrementally reaches the same place as one combined drag.
    ///
    /// A pan that cannot be represented is refused, like an unrepresentable
    /// zoom — including one reached by accumulating ordinary finite drags
    /// (Codex round 4).
    public func dragged(by delta: ViewPoint) -> StageTransform {
        let translated = ViewPoint(x: translation.x + delta.x, y: translation.y + delta.y)
        guard translated.x.isFinite, translated.y.isFinite else { return self }
        return StageTransform(scale: scale, translation: translated)
    }
}
