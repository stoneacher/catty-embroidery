import StagePreview
import SwiftUI

/// The hoop and the two fields, drawn first in the renderer's own `Canvas` pass.
///
/// **The hoop is an outline and is not clipped to.** Nothing here masks the renderer, so a
/// design that leaves the hoop stays visible — and because the mat is a *different fill*
/// rather than just empty space, out-of-hoop stitches read as sitting off the fabric.
/// That is how the user learns the boundary exists before export tells them.
///
/// **This used to be a view of its own, `StageFieldView`, a sibling `Canvas` under the
/// renderer's — and that is what US-315 found.** A keyboard animating in or out resizes the
/// stage. US-315's probe logged one draw per `Canvas` per layout change, at the final size,
/// while SwiftUI animated the frame. The two siblings were not presented under the same
/// geometry while that happened: for
/// several frames the design spilled out of the hoop, past the mat and over the caption below
/// it. Captured on the simulator frame by frame; `.drawingGroup()` on the pair did not fix it,
/// and drawing both in one pass did, in every sampled frame. One pass is also an arrangement in
/// which the two *cannot* disagree, whatever SwiftUI does with an animating frame.
///
/// The price is that the field is now the renderer's job (`StagePreviewRenderer` says so): a
/// future renderer must draw it too, through `geometry` here, so the two cannot drift apart.
enum StageField {
    /// What one frame's field is drawn as, in view points. A value so a test can read it: the
    /// `GraphicsContext` it is drawn into cannot be.
    struct Geometry: Equatable {
        /// The mat: the canvas's whole size.
        let mat: CGRect
        /// The hoop's interior and outline, at the frame's transform.
        let hoop: CGRect
        let outlineWidth: Double
    }

    /// - Parameters:
    ///   - transform: the transform this frame strokes the design with — the *same* value, which
    ///     is the whole point of drawing the field in the same pass.
    ///   - size: the `Canvas`'s own size, not the viewport the `GeometryReader` measured. The two
    ///     differ by a fraction of a point in iPhone 17's default layout (measured: 256.83 against
    ///     257.0; backlog US-322), and the mat has to cover what is actually drawn.
    ///   - increasedContrast: Increase Contrast thickens the outline.
    static func geometry(
        transform: StageTransform,
        size: CGSize,
        increasedContrast: Bool
    ) -> Geometry {
        Geometry(
            mat: CGRect(origin: .zero, size: size),
            hoop: transform.viewRect(of: StageGeometry.box),
            outlineWidth: increasedContrast ? 2 : StageChrome.hoopLineWidth
        )
    }

    static func draw(_ field: Geometry, into context: inout GraphicsContext) {
        context.fill(Path(field.mat), with: .color(StageChrome.outsideField))
        context.fill(Path(field.hoop), with: .color(StageChrome.hoopField))
        context.stroke(
            Path(field.hoop), with: .color(StageChrome.hoopOutline), lineWidth: field.outlineWidth
        )
    }
}
