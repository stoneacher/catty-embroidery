@testable import catrobat_embroidery_ios
import EmbroideryEngine
import Samples
import StagePreview
import SwiftUI
import Testing
import UIKit

/// US-313b, at the layer only a hosted view can reach: that the catcher is actually *installed*
/// on the stage, and that what it drives reaches the renderer.
///
/// **Separate from `StageViewWiringTests` because the technique is different, not only because
/// of SwiftLint's 400-line limit.** That suite hosts a view once and reads what the renderer was
/// handed. These host it, walk the `UIView` hierarchy to find the coordinator, drive its action
/// methods, and force layout between steps — a sequence rather than a snapshot. The walk is of
/// the view hierarchy, not of the published accessibility tree, which is what separates it from
/// the test US-307 had to delete after it passed locally and failed unreproducibly on CI.
@MainActor
@Suite("Stage manipulation wiring")
struct StageManipulationWiringTests {
    /// Hosts the stage with an **observable** owner of the interaction, so a write from the
    /// coordinator invalidates the body the way it does in the running app.
    ///
    /// `StageViewWiringTests.stage(...)` defaults to `.constant(StageInteraction())`, and a
    /// constant binding **discards every write** — so it cannot be used for anything asserting
    /// that a manipulation changed something. `AppModel` is the production owner (ADR-023), so
    /// using it here keeps the harness and the app on the same wiring rather than inventing a
    /// second one.
    private struct Harness: View {
        /// Injected rather than `@State`-owned, so a test can read the committed interaction
        /// back. `@Bindable` is what turns an `@Observable` reference into the `$model.interaction`
        /// binding `RootView` passes in production.
        @Bindable var model: AppModel
        let renderer: RecordingRenderer
        let display: StitchDisplayList

        var body: some View {
            StageView(
                sample: SampleLibrary.all.first,
                display: display,
                runState: .finished(.programFinished),
                needle: nil,
                renderer: renderer,
                summary: .empty,
                interaction: $model.interaction,
                exportReadiness: .notRun,
                designName: .constant("OctagonRosette"),
                nameValidation: DesignName.validating("OctagonRosette"),
                onPlay: {},
                onStop: {},
                onCommitName: {}
            )
        }
    }

    /// Drives a hosted stage through the coordinator the catcher installed.
    private final class StubPinch: UIPinchGestureRecognizer {
        var stubState: UIGestureRecognizer.State = .possible
        var stubLocation: CGPoint = .zero

        override var state: UIGestureRecognizer.State {
            get { stubState }
            set { stubState = newValue }
        }

        override func location(in _: UIView?) -> CGPoint {
            stubLocation
        }
    }

    private final class StubTap: UITapGestureRecognizer {
        var stubLocation: CGPoint = .zero

        override func location(in _: UIView?) -> CGPoint {
            stubLocation
        }
    }

    /// A shorthand for the type these helpers return often enough that the full path hurts.
    private typealias Coordinator = StageManipulationCatcher.Coordinator

    /// A hosted view and the window keeping it alive. A named pair, so the helper's signature
    /// fits on one line and SwiftLint's two-member tuple cap is respected.
    private struct Hosted {
        let window: UIWindow
        let controller: UIViewController
    }

    /// Hosts a view and keeps the window alive, so the hierarchy can be walked and laid out
    /// again between steps — which `hosting(_:at:)` cannot do, since it releases its window.
    private static func hostingRetained(_ view: some View, at size: CGSize) -> Hosted {
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        return Hosted(window: window, controller: controller)
    }

    private static func catcherCoordinator(in root: UIView) -> Coordinator? {
        let owned = root.gestureRecognizers?
            .compactMap { $0.delegate as? StageManipulationCatcher.Coordinator }
        if let found = owned?.first { return found }
        for subview in root.subviews {
            if let found = catcherCoordinator(in: subview) {
                return found
            }
        }
        return nil
    }

    /// AC11. **The invariant ADR-030 §7 inherits, observed from the renderer's side.**
    ///
    /// While a manipulation is live the frame is re-stroked at `current` and the raster's key
    /// stays on `bake`, so the settled prefix is rasterised once — on commit. A view that
    /// committed continuously would show `bake` changing every frame, which is *worse* than no
    /// gesture at all: every frame would take the uncoarsened plan and re-rasterise the whole
    /// design. Only the renderer can see this, which is why it is asserted here rather than in
    /// the package.
    @Test func theRendererSeesLiveThenSettledAcrossAManipulation() {
        let renderer = RecordingRenderer()
        let model = AppModel()
        let hosted = Self.hostingRetained(
            Harness(model: model, renderer: renderer, display: StageRenderRecording.drawnList()),
            at: CGSize(width: 390, height: 700)
        )
        defer { hosted.window.isHidden = true }

        let coordinator = Self.catcherCoordinator(in: hosted.controller.view)
        #expect(coordinator != nil, "the catcher never reached the hierarchy")
        guard let coordinator, let tracking = Self.trackingView(in: hosted.controller.view) else { return }

        let pinch = StubPinch()
        pinch.stubLocation = CGPoint(x: 100, y: 200)
        renderer.invocations.removeAll()

        tracking.touchesArrived(2)
        pinch.stubState = .began
        coordinator.pinched(pinch)
        Self.layOutAgain(hosted)

        for scale in [1.4, 1.9, 2.3] {
            pinch.scale = scale
            pinch.stubState = .changed
            coordinator.pinched(pinch)
            Self.layOutAgain(hosted)
        }

        let live = renderer.invocations
            .filter { !$0.transform.canUseRaster }
            .map(\.transform.bake)
        #expect(live.count >= 2, "the manipulation produced no live frames")
        #expect(Set(live).count == 1, "the bake key moved during the manipulation")

        pinch.stubState = .ended
        coordinator.pinched(pinch)
        tracking.touchesLeft(2)
        Self.layOutAgain(hosted)

        #expect(
            renderer.invocations.last?.transform.canUseRaster == true, "the stage stayed live"
        )
    }

    /// AC6, at the layer the package cannot reach: that the view wires the double tap to the
    /// **toggle** rather than to the reset it shipped with. `beginToggle` had no call site in
    /// the app at all before this story, so this is new wiring, not a re-test of package math.
    @Test func theDoubleTapTogglesToTwiceTheFitAboutTheTappedPoint() {
        let renderer = RecordingRenderer()
        let model = AppModel()
        let hosted = Self.hostingRetained(
            Harness(model: model, renderer: renderer, display: StageRenderRecording.drawnList()),
            at: CGSize(width: 390, height: 700)
        )
        defer { hosted.window.isHidden = true }

        guard let coordinator = Self.catcherCoordinator(in: hosted.controller.view),
              let invocation = renderer.invocations.last
        else {
            #expect(Bool(false), "the hosted stage never reached the renderer")
            return
        }
        let viewport = invocation.viewport
        let fitted = StageTransform.fitting(
            StageGeometry.fitTarget(including: StageRenderRecording.drawnList().bounds), in: viewport
        )
        let tap = StubTap()
        tap.stubLocation = CGPoint(x: viewport.width / 4, y: viewport.height / 4)
        let grabbed = fitted.stagePoint(of: ViewPoint(x: viewport.width / 4, y: viewport.height / 4))

        coordinator.doubleTapped(tap)
        Self.layOutAgain(hosted)

        // **Asserted on the model, not on the rendered frame.** The frame a double tap produces
        // is the *interpolated* one — the toggle animates, so the first frame after the tap is
        // still at the fit, and an assertion on it measures the animation\'s first step rather
        // than its destination. `baseline(fitting:settlingAt: 1)` is where the toggle is going.
        #expect(model.interaction.isSettling, "the double tap did not start an animation")
        let destination = model.interaction.baseline(fitting: fitted, settlingAt: 1)

        #expect(abs(destination.scale - fitted.scale * StageInteraction.toggleStep) < 1e-6)
        // The tapped point is the fixed point: a toggle anchored on the viewport centre, or on
        // the origin, moves it — and so does the reset-to-fit this replaced.
        let stayed = destination.viewPoint(of: grabbed)
        #expect(abs(stayed.x - viewport.width / 4) < 1e-6)
        #expect(abs(stayed.y - viewport.height / 4) < 1e-6)
    }

    private static func trackingView(in root: UIView) -> StageTouchTrackingView? {
        if let found = root as? StageTouchTrackingView {
            return found
        }
        for subview in root.subviews {
            if let found = trackingView(in: subview) {
                return found
            }
        }
        return nil
    }

    /// Forces SwiftUI to re-evaluate the hosted body after a write, the way a display refresh
    /// would. Two passes because the write invalidates the outer body, whose layout then sizes
    /// the canvas the inner one draws into.
    private static func layOutAgain(_ hosted: Hosted) {
        hosted.window.setNeedsLayout()
        hosted.window.layoutIfNeeded()
        hosted.controller.view.setNeedsLayout()
        hosted.controller.view.layoutIfNeeded()
    }
}
