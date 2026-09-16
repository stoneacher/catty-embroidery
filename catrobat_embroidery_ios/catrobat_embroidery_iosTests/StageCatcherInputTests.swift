@testable import catrobat_embroidery_ios
import StagePreview
import SwiftUI
import Testing
import UIKit

/// The four numbers the coordinator hands the package: the pinch's scale and centroid, and the
/// pan's translation at its beginning and at every change.
///
/// **Split from `StageCatcherLifecycleTests` at SwiftLint's 400-line limit, and the seam is a
/// real one**: that suite asks *when* a manipulation commits, this one asks *what* it commits.
///
/// Every test here exists because a mutation survived. `swift-code-reviewer` replaced the pinch
/// centroid, the pan's beginning translation and its changes with constants, one at a time, and
/// the whole app suite stayed green each time — meaning the story's headline defect, lateral
/// movement dropped during a pinch, had no regression guard at all. `/codex-review` then added
/// the ordering between `beginManipulating` and the magnification limits, which no test exercised
/// because none began a pinch during a fit animation.
@MainActor
@Suite("Stage manipulation inputs")
struct StageCatcherInputTests {
    /// **The single input this whole story exists to deliver**, and it was unasserted until the
    /// review deleted the pan's `.changed` arm and watched the suite stay green
    /// (`swift-code-reviewer`, I4). The story's headline defect was that lateral movement during a
    /// pinch was dropped; nothing would have noticed if it still were.
    @Test func aPanCommitsTheTranslationItLastReported() {
        let recording = Recording()
        let wiring = CatcherHarness.wired(recording)
        let coordinator = wiring.coordinator
        let view = wiring.view
        let pan = StubPan()
        let probe = CatcherHarness.fit.stagePoint(of: CatcherHarness.viewport.center)

        view.touchesArrived(1)
        pan.stubTranslation = CGPoint(x: 17, y: 9)
        pan.stubState = .began
        coordinator.panned(pan)
        pan.stubTranslation = CGPoint(x: 57, y: 29)
        pan.stubState = .changed
        coordinator.panned(pan)
        pan.stubState = .ended
        coordinator.panned(pan)
        view.touchesLeft(1)

        let settled = recording.interaction.settled
        #expect(settled != nil)
        let landed = settled?.viewPoint(of: probe)
        #expect(abs((landed?.x ?? 0) - (CatcherHarness.viewport.center.x + 57)) < 1e-6)
        #expect(abs((landed?.y ?? 0) - (CatcherHarness.viewport.center.y + 29)) < 1e-6)
    }

    /// **The threshold is included and never subtracted** — ADR-028 measured that subtraction (a
    /// 101 pt drag showing 91 and committing 101) and removed it, and the coordinator's comment
    /// calls re-basing to zero "the single most likely wrong reflex in this file". This is the
    /// case that can see it: a pan that begins and ends without ever reporting a change, where
    /// the beginning translation is the whole of the gesture.
    @Test func aPanThatNeverChangesStillCommitsItsBeginningTranslation() {
        let recording = Recording()
        let wiring = CatcherHarness.wired(recording)
        let coordinator = wiring.coordinator
        let view = wiring.view
        let pan = StubPan()
        let probe = CatcherHarness.fit.stagePoint(of: CatcherHarness.viewport.center)

        view.touchesArrived(1)
        pan.stubTranslation = CGPoint(x: 17, y: 9)
        pan.stubState = .began
        coordinator.panned(pan)
        pan.stubState = .ended
        coordinator.panned(pan)
        view.touchesLeft(1)

        let landed = recording.interaction.settled?.viewPoint(of: probe)
        #expect(landed != nil)
        #expect(abs((landed?.x ?? 0) - (CatcherHarness.viewport.center.x + 17)) < 1e-6)
        #expect(abs((landed?.y ?? 0) - (CatcherHarness.viewport.center.y + 9)) < 1e-6)
    }

    /// **The pinch anchors about the fingers, not about the viewport's centre** — the other half
    /// of "each finger keeps the stage point it grabbed", and also unasserted until the review
    /// replaced the centroid with `.zero` and the suite stayed green (I5). The old sequence used a
    /// centroid that happened to *be* the viewport centre, which is exactly the fallback
    /// `StageManipulation.gesture(in:)` uses when no anchor was ever set — so a coordinator
    /// passing nothing through was indistinguishable from one passing the right thing.
    @Test func aPinchCommitsAboutTheCentroidItWasGiven() {
        let recording = Recording()
        let wiring = CatcherHarness.wired(recording)
        let coordinator = wiring.coordinator
        let view = wiring.view
        let pinch = StubPinch()
        let centroid = ViewPoint(x: 100, y: 200)
        let grabbed = CatcherHarness.fit.stagePoint(of: centroid)

        view.touchesArrived(2)
        pinch.stubLocation = CGPoint(x: centroid.x, y: centroid.y)
        pinch.stubState = .began
        coordinator.pinched(pinch)
        pinch.scale = 2
        pinch.stubState = .changed
        coordinator.pinched(pinch)
        pinch.stubState = .ended
        coordinator.pinched(pinch)
        view.touchesLeft(2)

        let settled = recording.interaction.settled
        #expect(settled != nil)
        #expect(abs((settled?.scale ?? 0) - CatcherHarness.fit.scale * 2) < 1e-6)
        // The point under the fingers stayed under the fingers.
        let stayed = settled?.viewPoint(of: grabbed)
        #expect(abs((stayed?.x ?? 0) - centroid.x) < 1e-6)
        #expect(abs((stayed?.y ?? 0) - centroid.y) < 1e-6)
    }
}
