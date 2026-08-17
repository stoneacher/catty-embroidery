/// The dot and thread geometry, ported from Catroid and expressed as a function of
/// the transform rather than of the device.
///
/// Pure `Double` arithmetic, so it lives in `StagePreview` (ADR-022) and is proven
/// under `swift test`; the *appearance* of a traversal — colour, opacity, dash —
/// belongs to the app, because that is chrome and this is geometry.
public enum StitchDrawMetrics {
    /// Catroid's `BrickValues.STITCH_SIZE` (`BrickValues.java:187`), read as **stage
    /// points**.
    ///
    /// The reinterpretation is exact rather than approximate, and it is worth
    /// spelling out because "3.15" alone says nothing. On the Catroid side it is a
    /// *device-pixel* constant, converted into virtual-stage units by `screenRatio`
    /// (`EmbroideryActor.kt:39`) and then drawn under the batch's projection matrix.
    /// `DSTFileConstants.java:56` pins Catroid's `STITCH_POINT_UNIT_FACTOR = 2f` —
    /// the same factor ADR-007 pins for our stage — so one Catroid virtual unit *is*
    /// one of our stage points, and at the ordinary `screenRatio ≈ 1` the ported
    /// value is 3.15 stage points: **0.63 mm of fabric**, pinned by a test so the
    /// number cannot drift into meaning view points or millimetres.
    public static let stitchSizeInStagePoints: Double = 3.15

    /// Below this a thread is sub-pixel and the design silently vanishes. At
    /// `StageTransform.minimumScale` the unfloored width is 3.15 × 0.05 ≈ 0.16 pt.
    ///
    /// A **legibility** decision about chrome, not a claim about the design's
    /// physical size — which is why it is a separate named constant rather than a
    /// clamp folded into `stitchSizeInStagePoints`.
    public static let minimumWidthInViewPoints: Double = 0.75

    /// Constant in view space, deliberately **not** scaled by the transform.
    ///
    /// A traversal is chrome (the machine trims travel), and travel must stay
    /// subordinate to the stitches around it: a hairline that grew with zoom would
    /// become a ribbon competing with the thread it is annotating.
    public static let traversalWidthInViewPoints: Double = 1

    /// The thread's stroke width in view points at a given transform scale.
    ///
    /// This is the deviation from Catty that matters most in practice. Catty derives
    /// its width from the **device** diagonal and the project's virtual size, once,
    /// at stream init (`EmbroideryStream.swift:54-66`), so it cannot respond to zoom
    /// at all. (The story blamed rotation; that was the wrong indictment —
    /// `UIScreen.main.nativeBounds` is orientation-independent. The defect is the
    /// device derivation itself.) Ours is a function of the transform, so zooming in
    /// thickens the thread exactly as much as it enlarges the design.
    ///
    /// The floor is spelled `max(floor, scaled)` rather than `max(scaled, floor)` on
    /// purpose: `Swift.max` returns its first argument when the second is NaN, so
    /// this ordering collapses a NaN scale to the floor instead of propagating it
    /// into a `Path`. `StageTransform`'s constructor already makes a NaN scale
    /// unrepresentable, so this is belt-and-braces at zero cost — not a second
    /// guard anyone should rely on.
    public static func threadWidth(atScale scale: Double) -> Double {
        Swift.max(minimumWidthInViewPoints, stitchSizeInStagePoints * scale)
    }

    /// The penetration dot's radius — **the same value as the thread width**, which
    /// is Catroid's rule: it feeds the identical scalar to `circle` as a *radius* and
    /// to `rectLine` as a *width* (`EmbroideryActor.kt:83, 88-94`).
    ///
    /// So a dot's **diameter is twice** the thread's width, and that beading is what
    /// makes penetration points read as points. Do not "fix" it. Catty is the
    /// counter-example and is not followed: it keeps a separate
    /// `stitchingCircleRadius = 3.0` (`SpriteKitDefines.swift:49`) and passes its
    /// width in as the circle's *stroke*, so "dot radius and thread width are the
    /// same value" is Catroid's rule alone, not something the references share.
    ///
    /// Named separately from `threadWidth` despite being equal, because the two mean
    /// different things and a future story may well need to part them.
    public static func dotRadius(atScale scale: Double) -> Double {
        threadWidth(atScale: scale)
    }
}
