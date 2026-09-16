@testable import catrobat_embroidery_ios
import EmbroideryEngine
import StagePreview
import SwiftUI

/// The renderer double the stage's hosted tests share, and the display list they draw.
///
/// **Extracted in US-313b, when a second suite needed it.** It lived inside
/// `StageViewWiringTests` from US-305; the manipulation's hosted tests need the same recorder,
/// and that file was already at SwiftLint's 400-line limit. Shared doubles have a precedent
/// here (`ExportDoubles.swift`), and duplicating a recorder would mean two definitions of "what
/// the renderer was handed" that could quietly disagree.
enum StageRenderRecording {
    /// Two stitches, enough to give the display list real bounds — which is what makes
    /// `StageTransform.fitting` produce something other than the hoop's own fit.
    static func drawnList() -> StitchDisplayList {
        var list = StitchDisplayList()
        list.append(contentsOf: [
            PreviewStitch(position: StagePoint(x: 0, y: 0), color: .black),
            PreviewStitch(position: StagePoint(x: 40, y: 20), color: .black)
        ])
        return list
    }
}

/// One call to the renderer, as it was made.
struct StageRenderInvocation {
    let display: StitchDisplayList
    let transform: StageRenderTransform
    let needle: PreviewNeedle?
    let viewport: ViewSize
}

/// Records what it was handed instead of drawing it.
///
/// A class, because recording is a side effect of a `View`'s `body` and a value type would
/// record into a copy.
@MainActor
final class RecordingRenderer: StagePreviewRenderer {
    var invocations: [StageRenderInvocation] = []

    func makeBody(
        display: StitchDisplayList,
        transform: StageRenderTransform,
        needle: PreviewNeedle?,
        viewport: ViewSize
    ) -> EmptyView {
        invocations.append(
            StageRenderInvocation(
                display: display, transform: transform, needle: needle, viewport: viewport
            )
        )
        return EmptyView()
    }
}
