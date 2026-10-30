import CoreGraphics
import StagePreview

/// Where the stage's baked raster lives and when a frame may use it (US-322; ADR-043's US-322
/// amendment).
///
/// **One value that the bake, its key, the composite guard and the draw all read**, so they
/// cannot disagree about the raster's size (PR #84 review: with the size computed in three
/// places, mutants that baked at one size and compared at another survived every test).
///
/// **Overscan, because the `Canvas` size cannot be predicted.** SwiftUI snaps a view's *edges*
/// to device pixels, so the size a `Canvas` is handed depends on where it sits on the pixel grid,
/// not on the viewport's measured size alone — the same 770.5 px measurement was laid out as 770
/// and as 771 px at different offsets, and as `769.9999999999999` px rather than exactly 770
/// (reviewer's hosted probe). So the raster is baked one device pixel past the rounded-up
/// viewport on each axis, drawn at its own size from the origin, and used whenever the `Canvas`
/// fits inside it. It is never resampled, so it is never stretched; the `Canvas` clips the
/// overhang, and the seam with the live tail lines up because both are drawn from the origin.
struct RasterGeometry: Equatable {
    /// The size the raster is baked at and drawn at.
    let bakeSize: CGSize

    init(viewport: ViewSize, scale: CGFloat) {
        guard scale > 0 else {
            bakeSize = CGSize(width: viewport.width, height: viewport.height)
            return
        }
        func overscanned(_ points: Double) -> Double {
            ((points * scale).rounded(.up) + 1) / scale
        }
        bakeSize = CGSize(width: overscanned(viewport.width), height: overscanned(viewport.height))
    }

    /// Where the raster is drawn: at its own size, from the origin — never into the `Canvas`'s
    /// size, which is what would resample it.
    var drawRect: CGRect {
        CGRect(origin: .zero, size: bakeSize)
    }

    /// Whether this frame may composite the cached raster under the plan it draws.
    ///
    /// **Extracted so it can be tested at all** (`/codex-review` round 1, finding 3): it decides
    /// inside a `private` view's `Canvas` closure, which only runs when hosted *and* drawn. Three
    /// of its clauses are about *staleness* rather than liveness — nothing baked, a stale key, a
    /// `Canvas` the raster does not cover — which is why `forFrame` takes this as an input and
    /// asks `canUseRaster` itself. In each the frame draws the whole design and no raster.
    func composites(
        canUseRaster: Bool,
        bakedKey: AnyHashable?,
        expectedKey: AnyHashable,
        canvas: CGSize
    ) -> Bool {
        canUseRaster
            && bakedKey == expectedKey
            // Covers the `Canvas` on both axes; a hair of tolerance for SwiftUI's edge arithmetic
            // (`769.9999999999999` px), far below a pixel, so it never admits an unbaked strip.
            && canvas.width <= bakeSize.width + 1e-9
            && canvas.height <= bakeSize.height + 1e-9
    }
}
