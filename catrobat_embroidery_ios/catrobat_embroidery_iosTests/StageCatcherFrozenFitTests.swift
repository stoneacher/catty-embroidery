@testable import catrobat_embroidery_ios
import StagePreview
import SwiftUI
import Testing
import UIKit

/// US-314 at the layer the package suite cannot see: the coordinator, which is where the frozen
/// fit is captured and — the gap the story names — where a cancel has to reach it.
///
/// Every other catcher test holds one snapshot for the whole sequence. These re-deliver the
/// snapshot mid-manipulation with a **grown** fit, the way `updateUIView` does when a run
/// stitches past the hoop, built through the same `fitTarget(including:)` path `StageCanvas`
/// takes rather than from a hand-picked scale.
@MainActor
@Suite("Stage catcher frozen fit")
struct StageCatcherFrozenFitTests {
    enum FirstChannel: CaseIterable, Sendable {
        case pan
        case pinch
    }

    private static let viewport = CatcherHarness.viewport
    private static let centroid = CGPoint(x: 200, y: 400)

    /// A design stitched well past the hoop's right edge.
    private static var grown: StageTransform {
        StageTransform.fitting(
            StageGeometry.fitTarget(
                including: StageBox(minX: -250, minY: -250, maxX: 1250, maxY: 250)
            ),
            in: viewport
        )
    }

    private static func frame(
        _ recording: Recording,
        at fit: StageTransform
    ) -> StageRenderTransform {
        recording.interaction.rendering(
            gesture: recording.manipulation.gesture(in: viewport), fitting: fit, in: viewport
        )
    }

    @Test("the grown fit really differs from the hoop's")
    func theGrownFitDiffers() {
        #expect(Self.grown.scale < CatcherHarness.fit.scale)
    }

    // MARK: - AC3: begin → cancel → render at a changed fit

    @Test func aCancelledManipulationRendersAtTheNewFit() {
        let recording = Recording()
        let wiring = CatcherHarness.wired(recording)
        let pinch = StubPinch()
        let pan = StubPan()

        wiring.view.touchesArrived(2)
        pinch.stubLocation = Self.centroid
        pinch.stubState = .began
        wiring.coordinator.pinched(pinch)
        pinch.scale = 2
        pinch.stubState = .changed
        wiring.coordinator.pinched(pinch)
        pinch.stubState = .cancelled
        wiring.coordinator.pinched(pinch)

        CatcherHarness.update(
            wiring, recording, snapshot: CatcherHarness.snapshot(fitted: Self.grown)
        )

        #expect(recording.interaction == StageInteraction(), "the cancel left a frozen fit")
        #expect(Self.frame(recording, at: Self.grown) == .settled(Self.grown))

        // The next manipulation starts from the fit on screen now.
        wiring.view.touchesLeft(2)
        wiring.view.touchesArrived(1)
        pan.stubState = .began
        wiring.coordinator.panned(pan)
        #expect(Self.frame(recording, at: Self.grown).current == Self.grown)
    }

    // MARK: - AC5 through the coordinator: the second channel sees the grown fit

    /// Parameterised over the first channel because each recogniser's `.began` arm calls
    /// `beginManipulating` on its own: moving it after the channel's begin in *either* arm makes
    /// the tracker look live already, and that arm stops capturing.
    @Test(arguments: FirstChannel.allCases)
    func aSecondChannelAfterTheFitChangedStaysFrozen(first: FirstChannel) {
        let recording = Recording()
        let wiring = CatcherHarness.wired(recording)
        let pinch = StubPinch()
        let pan = StubPan()
        pinch.stubLocation = Self.centroid

        wiring.view.touchesArrived(2)
        let beginPinch = {
            pinch.stubState = .began
            wiring.coordinator.pinched(pinch)
        }
        let beginPan = {
            pan.stubState = .began
            wiring.coordinator.panned(pan)
        }
        switch first {
        case .pan: beginPan()
        case .pinch: beginPinch()
        }
        CatcherHarness.update(
            wiring, recording, snapshot: CatcherHarness.snapshot(fitted: Self.grown)
        )
        switch first {
        case .pan: beginPinch()
        case .pinch: beginPan()
        }
        pinch.scale = 2
        pinch.stubState = .changed
        wiring.coordinator.pinched(pinch)

        let last = Self.frame(recording, at: Self.grown)
        #expect(last == Self.frame(recording, at: CatcherHarness.fit))
        #expect(last.bake == CatcherHarness.fit)

        pinch.stubState = .ended
        wiring.coordinator.pinched(pinch)
        pan.stubState = .ended
        wiring.coordinator.panned(pan)
        wiring.view.touchesLeft(2)

        #expect(recording.commits == 1)
        #expect(recording.interaction.settled == last.current)
    }
}
