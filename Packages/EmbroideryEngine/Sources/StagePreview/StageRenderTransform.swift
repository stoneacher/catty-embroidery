/// What the stage draws with **and** what its cached raster is keyed on — two transforms,
/// because during a gesture they are deliberately different.
///
/// **This type exists because "blit the rendered layer" is not the same as "render".** The
/// first shipped design moved the already-rendered canvas with `.scaleEffect`/`.offset`,
/// which keeps the transform — and so the bake key — still during a gesture, exactly as
/// ADR-009 wants. What it cannot do is reveal anything: a `Canvas` rasterises only its own
/// bounds, so content that was off-screen was *never drawn*, and sliding the layer back
/// exposes blank space until the commit re-renders. Reported from the running app after the
/// first version shipped, and it is the defect `swift-architect` predicted in a form I
/// dismissed — I argued that scaling the whole canvas moves everything together, which is
/// true of the field and the stitches relative to each other and says nothing about content
/// outside the surface.
///
/// So the frame is re-stroked at `current` while `bake` stays where it was. The expensive
/// half of ADR-009 — rasterising the settled prefix — still happens exactly once per gesture,
/// on commit, which is what criterion 3 is actually protecting; the cheap half, re-stroking
/// the plan, happens per frame and is what US-309 measures separately for the mid-gesture
/// path.
public enum StageRenderTransform: Hashable, Sendable {
    /// No gesture and no animation: one transform for the raster and for the frame.
    case settled(StageTransform)

    /// A gesture or a fit animation in flight. The raster stays keyed on `bake` — so it is
    /// not rebuilt while the user's fingers are down — and the frame is drawn at `current`.
    case live(bake: StageTransform, current: StageTransform)

    /// What a cached raster may be keyed on. **Never `current`**: keying on that is precisely
    /// the per-frame re-bake ADR-009's cache exists to avoid.
    public var bake: StageTransform {
        switch self {
        case let .settled(transform): transform
        case let .live(bake, _): bake
        }
    }

    /// What this frame draws with.
    public var current: StageTransform {
        switch self {
        case let .settled(transform): transform
        case let .live(_, current): current
        }
    }

    /// Whether the cached raster may be composited at all this frame.
    ///
    /// `false` while live: the raster's pixels were baked at `bake`, so drawing them under a
    /// tail stroked at `current` would misplace them. The frame strokes the whole design instead
    /// — correct at any transform, and what makes it able to *reveal* content the previous frame
    /// had off-screen.
    ///
    /// **It is no longer stroked at full fidelity, and it was never "cheap".** This comment used
    /// to end "cheap at the counts M3 reaches", written against 2 976 stitches; ADR-029 names that
    /// sentence as the one US-309 invalidated, measuring 69.1 ms per drawn frame at 50 000. Since
    /// US-310 this predicate is what `StitchDrawPlan.forFrame(of:at:compositingRaster:…)` keys on
    /// to hand back a **coarse** plan (ADR-030 rung 2), so `false` here now costs fidelity while
    /// a finger is down rather than frame time.
    public var canUseRaster: Bool {
        switch self {
        case .settled: true
        case .live: false
        }
    }
}
