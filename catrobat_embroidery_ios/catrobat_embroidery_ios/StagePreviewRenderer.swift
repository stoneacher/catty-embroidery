import StagePreview
import SwiftUI

/// How the stage draws a display list. ADR-009's escape hatch, as a type.
///
/// **There is deliberately no `GraphicsContext` in this signature.** A context here
/// would be the `Canvas` leaking into the abstraction and would defeat the whole
/// purpose: `CanvasStitchRenderer` returns a `Canvas`, and a future
/// `MetalStitchRenderer` must be able to return something else entirely. That is why
/// the requirement is an `associatedtype Body: View` rather than a drawing call.
///
/// Every parameter is a `StagePreview` type, not a CoreGraphics one — `ViewSize`
/// rather than `CGSize`, `StageTransform` rather than `CGAffineTransform`. CoreGraphics
/// enters in exactly one file (`StageTransform+CoreGraphics.swift`), which keeps
/// ADR-022's boundary checkable rather than aspirational.
///
/// `makeBody` and not `body`: `body` reads as SwiftUI's own computed property and would
/// collide the moment someone conformed a `View` to this. `makeBody` follows
/// `ViewModifier`/`Layout`.
@MainActor
protocol StagePreviewRenderer {
    associatedtype Body: View

    /// - Parameters:
    ///   - display: what has been stitched, append-only (ADR-021).
    ///   - transform: the stage → view mapping for this frame, and — separately — the one
    ///     any cached raster may be keyed on. The two differ while a gesture or the fit
    ///     animation is in flight, which is what lets the frame be re-stroked at the live
    ///     transform without rebuilding the settled raster sixty times a second. Was a bare
    ///     `StageTransform` in US-305; widened in US-307, when moving the *rendered layer*
    ///     instead turned out to be unable to reveal anything the canvas had not drawn.
    ///   - needle: the needle's pose. **Always `nil` in US-305** — nothing in this
    ///     story produces a run, and US-306 owns the needle indicator's appearance and
    ///     accessibility. It is in the signature from the start anyway, because adding
    ///     a protocol requirement later would change every conformance including the
    ///     test double, and `PreviewNeedle` already exists so the parameter is not
    ///     speculative.
    ///   - viewport: the size the renderer has to fill, in view points.
    func makeBody(
        display: StitchDisplayList,
        transform: StageRenderTransform,
        needle: PreviewNeedle?,
        viewport: ViewSize
    ) -> Body
}
