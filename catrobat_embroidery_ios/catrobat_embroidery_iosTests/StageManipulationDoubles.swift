@testable import catrobat_embroidery_ios
import StagePreview
import SwiftUI
import UIKit

/// The doubles the catcher's two suites share: three stub recognisers, a recording of what the
/// coordinator wrote, and a wired coordinator to drive.
///
/// **The stubs override rather than assign, and that was measured.** The story's test plan
/// proposes `import UIKit.UIGestureRecognizerSubclass` and a settable `state`, flagging the
/// premise as one to verify at the red phase rather than take from the plan. Verified on a
/// booted iPhone 17: the import compiles and `state` *is* assignable, and the assignment is
/// **silently swallowed** — `state` stays `.possible`, no action ever dispatches,
/// `setTranslation(_:in:)` does nothing and `location(in:)` returns `.zero`. A coordinator
/// switching on a stub built that way would take no branch at all, and its tests would be green
/// for the wrong reason. Overriding works, including through the base type, because ObjC
/// dispatches dynamically. `scale` needs no override: it is genuinely settable.
///
/// **Nothing here synthesises a touch**, because nothing can — `UITouch` has no public
/// initialiser. The touch *count* is the tracking view's seam instead, which is honest about
/// what these assert: the coordinator's response to a touch sequence, not UIKit's delivery of
/// one. The delivery is human checks 1–3, on a device.
/// Overrides rather than assigns; see the suite comment.
final class StubPinch: UIPinchGestureRecognizer {
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

final class StubPan: UIPanGestureRecognizer {
    var stubState: UIGestureRecognizer.State = .possible
    var stubTranslation: CGPoint = .zero

    override var state: UIGestureRecognizer.State {
        get { stubState }
        set { stubState = newValue }
    }

    override func translation(in _: UIView?) -> CGPoint {
        stubTranslation
    }
}

final class StubTap: UITapGestureRecognizer {
    var stubLocation: CGPoint = .zero

    override func location(in _: UIView?) -> CGPoint {
        stubLocation
    }
}

/// Holds what the bindings write, and counts the commits the coordinator reports.
///
/// A local class per test rather than anything shared: these suites run in parallel.
final class Recording {
    var manipulation = StageManipulation()
    var interaction = StageInteraction()
    var commits = 0
    var taps: [ViewPoint] = []
}

/// The fixture the two catcher suites share: a viewport, its fit, and a coordinator wired to a
/// recording and installed on a real tracking view.
///
/// Each call builds everything fresh, so nothing is shared between tests that run in parallel —
/// the recording is the caller's own object.
@MainActor
enum CatcherHarness {
    /// Deliberately not square, so an implementation that uses one extent for both axes fails.
    static let viewport = ViewSize(width: 400, height: 800)

    static var fit: StageTransform {
        StageTransform.fitting(StageGeometry.box, in: viewport)
    }

    static func snapshot(settlingAt progress: Double = 1) -> StageManipulationCatcher.Snapshot {
        StageManipulationCatcher.Snapshot(
            fitted: fit, viewport: viewport, settlingProgress: progress
        )
    }

    /// A coordinator and the view it is installed on. A named pair rather than a tuple, which
    /// SwiftLint caps at two members and which reads worse at every call site.
    struct Wiring {
        let coordinator: StageManipulationCatcher.Coordinator
        let view: StageTouchTrackingView
    }

    static func wired(_ recording: Recording, settlingAt progress: Double = 1) -> Wiring {
        let coordinator = StageManipulationCatcher.Coordinator()
        let view = StageTouchTrackingView()
        coordinator.install(on: view)
        coordinator.update(
            snapshot: snapshot(settlingAt: progress),
            manipulation: Binding(
                get: { recording.manipulation }, set: { recording.manipulation = $0 }
            ),
            interaction: Binding(
                get: { recording.interaction }, set: { recording.interaction = $0 }
            ),
            onDoubleTap: { recording.taps.append($0) },
            onCommitted: { recording.commits += 1 }
        )
        return Wiring(coordinator: coordinator, view: view)
    }
}
