#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

/// The needle indicator's geometry — greenfield on both platforms, so judged on ADR-009
/// cost and accessibility rather than on parity. Catroid's "needle" is an ordinary sprite
/// with a PNG look; Catty has zero occurrences of "needle" in `src/`.
///
/// **Every number here is in view points, and none of them is a function of the
/// transform.** This is a UI indicator, not design data: it marks *where the machine is*,
/// and a marker that grew with US-307's pinch-zoom would stop being a marker and start
/// looking like a very large stitch. `StitchDrawMetrics` is the opposite kind of type —
/// stage-scaled geometry ported from Catroid, where every member takes an `atScale:` — so
/// these constants deliberately do not live there and none of them takes a scale. What
/// they share is `StitchDrawMetrics.traversalWidthInViewPoints`' principle: chrome is
/// constant in view space.
///
/// Known limitation US-307 inherits, recorded because the fixed size is a decided
/// constraint and this is its price: the thread stroke reaches the needle's width at
/// `scale ≈ 2.86` and its length at `scale ≈ 3.49`, so past roughly 3× zoom the needle is
/// comparable to a single thread stroke and stops reading as a distinct marker. It is
/// never *occluded* — it is drawn in a layer above everything — only dwarfed. If that
/// turns out to matter the fix is a floor, not a scale factor.
public enum NeedleGlyph {
    /// Tip → shoulders, along the heading.
    public static let length: Double = 11

    /// Half the shoulder span.
    public static let halfWidth: Double = 4.5

    /// Where the trailing edge dips back toward the tip, which is what makes the shape
    /// read as a dart pointing somewhere rather than as a cone.
    public static let notchLength: Double = 8.5

    /// Stroked **centred** on the outline, so the fill covers its inner half and exactly
    /// `haloWidth / 2` survives outside the silhouette. One path, two draws — no second
    /// geometry to keep in sync.
    public static let haloWidth: Double = 3

    /// Increase Contrast widens the halo to 2 pt visible. Opacity and width are precisely
    /// what that setting exists to undo, so the setting gets the width rather than a
    /// different colour — and because the needle is live-pass only, unlike US-305's
    /// travel stroke this costs nothing in a cache key.
    public static let increasedContrastHaloWidth: Double = 4

    /// The outline in glyph space: tip at the origin, body extending toward +y, so the
    /// needle faces **screen up** at heading 0. Tip first, then clockwise.
    static let localOutline: [ViewPoint] = [
        ViewPoint(x: 0, y: 0),
        ViewPoint(x: halfWidth, y: length),
        ViewPoint(x: 0, y: notchLength),
        ViewPoint(x: -halfWidth, y: length)
    ]

    /// The outline placed at `tip` and rotated to `heading`, or `nil` if either is
    /// unusable.
    ///
    /// **ADR-007's convention, and why the rotation carries no sign flip and no 90°
    /// offset.** The ADR pins degrees with 0° = up, x via sin and y via cos — so a
    /// heading θ points along `(sin θ, cos θ)` in *stage* space, which is y-up.
    /// `StageTransform.viewPoint(of:)` applies the renderer's single y-flip, so the same
    /// direction in view space is `(sin θ, −cos θ)`. The standard rotation matrix
    /// `[[cos, −sin], [sin, cos]]` sends the glyph's forward vector `(0, −1)` to
    /// `(sin θ, −cos θ)` — exactly that. **Two flips cancel**: the flip that makes the
    /// *position* y-down also reverses the handedness of the *rotation*, so the engine's
    /// angle goes in unmodified.
    ///
    /// A negated angle, or a −90° offset, is the mistake this comment exists to prevent,
    /// and `NeedleGlyphTests.theGlyphFacesWhereTheEngineWouldStep` pins it
    /// *differentially* — against a step taken through the real transform — rather than
    /// by trusting this argument or a table of coordinates.
    ///
    /// The `nil` return follows the renderer's existing non-finite policy: ADR-021
    /// divergence #5 lets a coordinate the stream rejects reach the display trace, and
    /// `changeXBy` accumulates to infinity from a legal program, so a non-finite needle
    /// position is reachable rather than theoretical.
    public static func outline(at tip: ViewPoint, heading: Double) -> [ViewPoint]? {
        guard tip.x.isFinite, tip.y.isFinite, heading.isFinite else { return nil }

        // **A finite heading is not enough to give finite geometry**, which is why the angle is
        // reduced before it is scaled. `heading * .pi / 180` *overflows to infinity* for a
        // heading near `.greatestFiniteMagnitude`, and `sin`/`cos` of infinity are NaN — so the
        // guard above passed and the function returned non-finite points anyway, contradicting
        // its own contract (Codex round 1). The normal interpreter path normalises headings, so
        // the stage was insulated; this is a `public` API and its guard should not depend on
        // that.
        //
        // A remainder rather than a clamp, because rotation is periodic: reducing modulo 360
        // is exact for the angle's *meaning*, not a degradation of it.
        let radians = heading.truncatingRemainder(dividingBy: 360) * .pi / 180
        let sine = sin(radians)
        let cosine = cos(radians)

        return localOutline.map { local in
            ViewPoint(
                x: tip.x + cosine * local.x - sine * local.y,
                y: tip.y + sine * local.x + cosine * local.y
            )
        }
    }
}
