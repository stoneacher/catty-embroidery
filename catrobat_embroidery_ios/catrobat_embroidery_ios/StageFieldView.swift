import StagePreview
import SwiftUI

/// The hoop and the two fields, drawn beneath whatever the renderer produces.
///
/// **The hoop is an outline and is not clipped to.** Nothing here masks the renderer, so a
/// design that leaves the hoop stays visible — and because the mat is a *different fill*
/// rather than just empty space, out-of-hoop stitches read as sitting off the fabric.
/// That is how the user learns the boundary exists before export tells them.
struct StageFieldView: View {
    let transform: StageTransform

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)), with: .color(StageChrome.outsideField)
            )

            let hoop = transform.viewRect(of: StageGeometry.box)
            context.fill(Path(hoop), with: .color(StageChrome.hoopField))
            context.stroke(
                Path(hoop),
                with: .color(StageChrome.hoopOutline),
                lineWidth: contrast == .increased ? 2 : StageChrome.hoopLineWidth
            )
        }
        // Decorative: the caption below states the hoop's size, which is everything this
        // shape carries. Same reasoning as `StagePlaceholderView`'s outline.
        .accessibilityHidden(true)
    }
}
