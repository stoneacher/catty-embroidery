@testable import catrobat_embroidery_ios
import EmbroideryEngine
import Samples
import StagePreview
import SwiftUI
import Testing
import UIKit

/// US-305 items 1 and 8: what `StageView` **hands the renderer**, and that it hands
/// it nothing at all when there is nothing to draw.
///
/// This is the half of the story a `StitchDrawPlan` test cannot reach. The plan
/// proves the batching *logic*; these prove the *wiring* — that the view computes its
/// transform from the fit target and its own measured viewport, passes the display
/// list and needle through unchanged, and short-circuits to the empty state. The two
/// partition the story's test plan and overlap nowhere.
///
/// **These must host the view.** `StageView` measures itself with a `GeometryReader`,
/// whose closure does not run when `body` is merely read, so a test that constructs
/// the view and inspects it observes nothing. Hosting in a `UIWindow` at an explicit
/// frame and forcing layout is what makes the viewport real.
@MainActor
@Suite("Stage view wiring")
struct StageViewWiringTests {
    /// Records what it was handed instead of drawing it. A class, because recording is
    /// a side effect of a `View`'s `body` and a value type would record into a copy.
    /// One recorded call. A sibling of the renderer rather than nested inside it, purely
    /// to stay within SwiftLint's one-level nesting limit.
    private struct Invocation {
        let display: StitchDisplayList
        let transform: StageTransform
        let needle: PreviewNeedle?
        let viewport: ViewSize
    }

    @MainActor
    private final class RecordingRenderer: StagePreviewRenderer {
        var invocations: [Invocation] = []

        func makeBody(
            display: StitchDisplayList,
            transform: StageTransform,
            needle: PreviewNeedle?,
            viewport: ViewSize
        ) -> EmptyView {
            invocations.append(
                Invocation(display: display, transform: transform, needle: needle, viewport: viewport)
            )
            return EmptyView()
        }
    }

    /// Hosts `view` at `size` and forces a layout pass, so every `GeometryReader`
    /// inside it has run by the time this returns.
    ///
    /// The window is retained for the duration of the call and released after: a
    /// `UIWindow` left alive across tests would leak between them, and these run in
    /// parallel.
    private static func hosting(_ view: some View, at size: CGSize) {
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
    }

    private static func drawnList() -> StitchDisplayList {
        var list = StitchDisplayList()
        list.append(contentsOf: [
            PreviewStitch(position: StagePoint(x: 0, y: 0), color: .black),
            PreviewStitch(position: StagePoint(x: 40, y: 20), color: .black)
        ])
        return list
    }

    /// Builds the stage with the story's new parameters defaulted, so that adding one
    /// more does not mean editing every call site again — and so each test states only
    /// the input it is about.
    private static func stage(
        display: StitchDisplayList,
        needle: PreviewNeedle?,
        renderer: RecordingRenderer,
        runState: RunState = .running
    ) -> some View {
        StageView(
            sample: SampleLibrary.all.first,
            display: display,
            runState: runState,
            needle: needle,
            renderer: renderer,
            onPlay: {},
            onStop: {}
        )
    }

    /// Item 1.
    ///
    /// **The transform is checked against the viewport the renderer was actually
    /// handed, not against a hard-coded number.** The canvas is inset by padding and
    /// shares the pane with a caption, so its size is not the window's and predicting
    /// it here would be a test of SwiftUI's layout arithmetic rather than of this
    /// view. What matters — and what this asserts — is that the transform is the one
    /// `StageGeometry.fitTarget` + `StageTransform.fitting` produce *for that
    /// viewport*: a view that fitted the raw content bounds, or the hoop alone, or a
    /// stale viewport, all fail here.
    @Test func theRendererIsHandedTheDisplayListTransformAndViewportForItsSize() {
        let renderer = RecordingRenderer()
        let list = Self.drawnList()

        Self.hosting(
            Self.stage(display: list, needle: nil, renderer: renderer),
            at: CGSize(width: 390, height: 700)
        )

        let invocation = renderer.invocations.last
        #expect(invocation != nil, "a non-empty display list must reach the renderer")
        guard let invocation else { return }

        #expect(invocation.display == list)
        #expect(invocation.viewport.width > 0)
        #expect(invocation.viewport.height > 0)
        #expect(invocation.viewport.width <= 390)
        #expect(invocation.viewport.height <= 700)

        let expected = StageTransform.fitting(
            StageGeometry.fitTarget(including: list.bounds), in: invocation.viewport
        )
        #expect(invocation.transform == expected)
    }

    @Test func theRendererIsHandedTheNeedleUnchanged() {
        let renderer = RecordingRenderer()
        let needle = PreviewNeedle(
            actor: ActorID(0), update: NeedleUpdate(position: StagePoint(x: 1, y: 2), heading: 90)
        )

        Self.hosting(
            Self.stage(display: Self.drawnList(), needle: needle, renderer: renderer),
            at: CGSize(width: 390, height: 700)
        )

        #expect(renderer.invocations.last?.needle == needle)
    }

    /// US-306: the design stays drawn after the run ends.
    ///
    /// Catroid's precedent is the same — `StageListener.render()` calls `stage.draw()`
    /// whenever `!finished`, regardless of pause — and it is what makes "press stop and
    /// still have my design" true on screen rather than only in the model.
    @Test func theRendererStillDrawsAfterTheRunFinishes() {
        let renderer = RecordingRenderer()

        Self.hosting(
            Self.stage(
                display: Self.drawnList(),
                needle: nil,
                renderer: renderer,
                runState: .finished(.stoppedByUser)
            ),
            at: CGSize(width: 390, height: 700)
        )

        #expect(!renderer.invocations.isEmpty, "a finished run must keep its design on screen")
    }

    /// Item 8. The "never invoked" half is what a screenshot cannot claim: a renderer
    /// handed an empty list could perfectly well draw an empty canvas, and the
    /// resulting screenshot would be indistinguishable from the empty state.
    @Test func anEmptyDisplayListShowsThePressPlayStateAndNeverInvokesTheRenderer() {
        let renderer = RecordingRenderer()

        Self.hosting(
            Self.stage(display: StitchDisplayList(), needle: nil, renderer: renderer),
            at: CGSize(width: 390, height: 700)
        )

        #expect(renderer.invocations.isEmpty)
    }
}

/// The three states the stage can be in, as a pure function — so item 8's branch is
/// assertable without a view at all.
@Suite("Stage content state")
struct StageContentStateTests {
    @Test func nothingSelectedIsTheNoSelectionState() {
        #expect(StageContentState.resolving(hasSelection: false, hasStitches: false) == .noSelection)
    }

    @Test func aSelectionWithNoStitchesIsTheReadyState() {
        #expect(StageContentState.resolving(hasSelection: true, hasStitches: false) == .notRun)
    }

    @Test func aSelectionWithStitchesIsDrawn() {
        #expect(StageContentState.resolving(hasSelection: true, hasStitches: true) == .drawn)
    }

    /// Not reachable today — nothing clears a selection, and only a selected sample
    /// produces stitches — but total rather than trapping, and it resolves toward
    /// *showing the stitches*: real content on screen beats telling the user nothing
    /// is selected while their design is visibly there.
    @Test func stitchesWithoutASelectionStillDraw() {
        #expect(StageContentState.resolving(hasSelection: false, hasStitches: true) == .drawn)
    }
}
