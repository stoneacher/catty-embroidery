import StagePreview
import Testing

/// **Two fingers, reduced to a `StageGesture` — the input layer US-313a adds.**
///
/// The shipped stage composes `MagnifyGesture` with `DragGesture` and feeds the drag's
/// translation into `StageGesture.pan`. `DragGesture` is a single-touch recogniser: with two
/// fingers down its translation is not the centroid's, so lateral movement during a pinch is
/// largely dropped. That is the whole defect, and it is an *input* defect —
/// `StageInteraction.moved(by:from:fitting:in:)` already composes
/// `pinched(by: m, about: c₀).dragged(by: p)`, which maps a point at `x₀` to `m(x₀ − c₀) + p + c₀`
/// and is therefore *exactly* native two-finger manipulation once `p` is the centroid delta.
///
/// So these tests observe **fingers**, not the tracker's fields. The tempting spellings —
/// "the anchor equals the start centroid", "the pan equals the centroid delta" — restate the
/// implementation and would survive a mutation of it, which is precisely the survivor US-309
/// found. Every discriminating test below asks where a *grabbed stage point* ended up.
@Suite("Stage manipulation")
struct StageManipulationTests {
    private static let viewport = ViewSize(width: 390, height: 500)

    private static var fit: StageTransform {
        StageTransform.fitting(StageGeometry.box, in: viewport)
    }

    /// Two touches, so a test can say where fingers are rather than what the recognisers report.
    private struct Fingers {
        var a: ViewPoint
        var b: ViewPoint

        var centroid: ViewPoint {
            ViewPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }

        var separation: Double {
            let dx = b.x - a.x
            let dy = b.y - a.y
            return (dx * dx + dy * dy).squareRoot()
        }
    }

    private static func delta(from start: ViewPoint, to end: ViewPoint) -> ViewPoint {
        ViewPoint(x: end.x - start.x, y: end.y - start.y)
    }

    private static func isClose(
        _ actual: ViewPoint,
        _ expected: ViewPoint,
        within tolerance: Double = 1e-9
    ) -> Bool {
        abs(actual.x - expected.x) < tolerance && abs(actual.y - expected.y) < tolerance
    }

    /// Where the stage lands for a gesture, from a fresh interaction following the fit.
    private static func transform(for gesture: StageGesture) -> StageTransform {
        StageInteraction().transform(with: gesture, fitting: fit, in: viewport)
    }

    // MARK: - The manipulation is native

    /// **The story's reason to exist.** Two fingers pinch *and* translate at once; each must
    /// keep the stage point it grabbed. Nothing here mentions an anchor or a pan — it asks only
    /// where two grabbed points ended up, so a wrong rule has nowhere to hide.
    @Test("both fingers stay under the stage points they grabbed")
    func bothFingersStayUnderTheStagePointsTheyGrabbed() throws {
        let start = Fingers(a: ViewPoint(x: 100, y: 200), b: ViewPoint(x: 300, y: 400))
        let now = Fingers(a: ViewPoint(x: 140, y: 180), b: ViewPoint(x: 460, y: 500))
        let grabbedA = Self.fit.stagePoint(of: start.a)
        let grabbedB = Self.fit.stagePoint(of: start.b)

        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: start.centroid)
        manipulation.panChanged(to: Self.delta(from: start.centroid, to: now.centroid))
        manipulation.pinchChanged(to: now.separation / start.separation)

        let gesture = try #require(manipulation.gesture(in: Self.viewport))
        let transform = Self.transform(for: gesture)

        #expect(Self.isClose(transform.viewPoint(of: grabbedA), now.a))
        #expect(Self.isClose(transform.viewPoint(of: grabbedB), now.b))
    }

    /// A pinch that starts **after** the pan has already moved must be anchored in the
    /// *baseline* frame: `centroidAtPinchBegin − panAtPinchBegin`. Anchoring on the raw centroid
    /// leaves the result off by `(1 − m)·panAtPinchBegin`, which is a defect that only appears
    /// when a second finger lands mid-drag — the ordinary way a two-finger gesture starts.
    @Test("a pinch that begins after the pan has moved is anchored in the baseline frame")
    func aPinchThatBeginsAfterThePanHasMovedIsAnchoredInTheBaselineFrame() throws {
        let alreadyPanned = ViewPoint(x: 50, y: 20)
        let centroid = ViewPoint(x: 200, y: 300)
        // The stage point sitting under the centroid at the moment the pinch begins.
        let grabbed = Self.fit
            .dragged(by: alreadyPanned)
            .stagePoint(of: centroid)

        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.panChanged(to: alreadyPanned)
        manipulation.pinchBegan(scale: 1, centroid: centroid)
        manipulation.pinchChanged(to: 2)

        let gesture = try #require(manipulation.gesture(in: Self.viewport))

        // The fingers have not moved since the pinch began, so the grabbed point has not either.
        #expect(Self.isClose(Self.transform(for: gesture).viewPoint(of: grabbed), centroid))
    }

    /// The user's complaint, minimally: *"pinching really only zooms in/out of the canvas and
    /// does not register side-to-side movements in parallel."* Separation constant, centroid
    /// translating — the stage must translate by exactly that much.
    @Test("lateral centroid movement during a pinch moves the stage")
    func lateralCentroidMovementDuringAPinchMovesTheStage() throws {
        let start = Fingers(a: ViewPoint(x: 100, y: 240), b: ViewPoint(x: 300, y: 240))
        let sideways = ViewPoint(x: 90, y: -35)
        let now = Fingers(
            a: ViewPoint(x: start.a.x + sideways.x, y: start.a.y + sideways.y),
            b: ViewPoint(x: start.b.x + sideways.x, y: start.b.y + sideways.y)
        )

        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: start.centroid)
        manipulation.panChanged(to: Self.delta(from: start.centroid, to: now.centroid))
        manipulation.pinchChanged(to: now.separation / start.separation)

        let gesture = try #require(manipulation.gesture(in: Self.viewport))

        #expect(Self.transform(for: gesture) == Self.fit.dragged(by: sideways))
    }

    /// ADR-028's correctness clause, re-established across the new input path: recogniser values
    /// are cumulative from the gesture's start, so folding each callback in as a delta compounds
    /// it — 2, 2, 2 would land at 8× for fingers that only ever asked for 2×.
    @Test("the magnification is cumulative, never accumulated")
    func theMagnificationIsCumulativeNeverAccumulated() throws {
        var manipulation = StageManipulation()
        manipulation.pinchBegan(scale: 1, centroid: Self.viewport.center)
        manipulation.pinchChanged(to: 2)
        manipulation.pinchChanged(to: 2)
        manipulation.pinchChanged(to: 2)

        let gesture = try #require(manipulation.gesture(in: Self.viewport))

        #expect(gesture.magnification == 2)
    }

    // MARK: - One manipulation, one commit

    /// **The rule two recognisers make ambiguous.** A pinch ends when a finger lifts; a pan with
    /// `maximumNumberOfTouches = 2` carries on with the other. Committing at the *first* channel
    /// end would write `settled` twice for one manipulation — and therefore re-bake a
    /// 50 000-stitch prefix twice, back to back, at finger-lift, which is exactly where ADR-030
    /// says the tail already lives.
    @Test("ending one channel while the other is live produces no commit value")
    func endingOneChannelWhileTheOtherIsLiveProducesNoCommitValue() {
        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: Self.viewport.center)
        manipulation.panChanged(to: ViewPoint(x: 30, y: 10))
        manipulation.pinchChanged(to: 1.5)

        manipulation.pinchEnded()

        #expect(manipulation.finish(in: Self.viewport) == nil)
        #expect(manipulation.gesture(in: Self.viewport) != nil)
    }

    /// This is the assertion ADR-028 records as unobtainable: its
    /// `onlyTheFinalCumulativeValueIsApplied` collapsed to `once == once`, because "applied
    /// exactly once" was a fact about a SwiftUI view. Moving the decision into the package is
    /// what makes it a fact about a value.
    @Test("a manipulation yields exactly one commit value")
    func aManipulationYieldsExactlyOneCommitValue() {
        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: Self.viewport.center)
        manipulation.panChanged(to: ViewPoint(x: 30, y: 10))
        manipulation.pinchChanged(to: 1.5)

        manipulation.pinchEnded()
        manipulation.panEnded()

        #expect(manipulation.finish(in: Self.viewport) != nil)
        #expect(manipulation.finish(in: Self.viewport) == nil)
        #expect(manipulation.gesture(in: Self.viewport) == nil)
    }

    /// ADR-028's "live and committed are the same number by construction", preserved: what the
    /// last frame drew is what gets committed, so the stage cannot shift at finger-lift.
    @Test("the committed value is the last live value")
    func theCommittedValueIsTheLastLiveValue() throws {
        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: ViewPoint(x: 120, y: 260))
        manipulation.panChanged(to: ViewPoint(x: -14, y: 62))
        manipulation.pinchChanged(to: 2.25)

        let live = try #require(manipulation.gesture(in: Self.viewport))
        manipulation.pinchEnded()
        manipulation.panEnded()

        #expect(manipulation.finish(in: Self.viewport) == live)
    }

    /// A finger lifts, the other keeps dragging. The magnification must stay where the pinch
    /// left it: dropping it snaps the stage back toward 1× in the middle of a manipulation the
    /// user has not finished.
    @Test("a latched magnification survives the pinch ending")
    func aLatchedMagnificationSurvivesThePinchEnding() throws {
        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: ViewPoint(x: 200, y: 300))
        manipulation.pinchChanged(to: 2)
        manipulation.panChanged(to: ViewPoint(x: 40, y: 15))

        let before = try #require(manipulation.gesture(in: Self.viewport))
        manipulation.pinchEnded()
        let after = try #require(manipulation.gesture(in: Self.viewport))

        // Continuous across the channel end — the frame does not move because a finger left.
        #expect(Self.transform(for: after) == Self.transform(for: before))

        manipulation.panChanged(to: ViewPoint(x: 80, y: 15))
        let stillPanning = try #require(manipulation.gesture(in: Self.viewport))

        #expect(stillPanning.magnification == 2)
    }

    // MARK: - Lifecycle failures

    /// **The regression this approach risks and `@GestureState` cannot have.** SwiftUI clears a
    /// `@GestureState` when the system cancels a gesture; a UIKit coordinator does not. Miss
    /// `.cancelled` and an incoming call leaves the stage permanently live — `canUseRaster` false
    /// forever, the design coarse forever, and the settled raster never rebuilt.
    @Test("a cancelled manipulation commits nothing and clears liveness")
    func aCancelledManipulationCommitsNothingAndClearsLiveness() {
        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: Self.viewport.center)
        manipulation.panChanged(to: ViewPoint(x: 30, y: 10))
        manipulation.pinchChanged(to: 1.5)

        manipulation.cancelled()

        #expect(manipulation.gesture(in: Self.viewport) == nil)
        #expect(manipulation.finish(in: Self.viewport) == nil)
    }

    /// A cancelled manipulation must not poison the next one.
    @Test("a manipulation after a cancellation starts from nothing")
    func aManipulationAfterACancellationStartsFromNothing() throws {
        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.panChanged(to: ViewPoint(x: 120, y: 90))
        manipulation.cancelled()

        manipulation.panBegan(at: .zero)
        let gesture = try #require(manipulation.gesture(in: Self.viewport))

        #expect(gesture.isIdentity)
    }

    /// Four review rounds paid for this in `StageInteraction`, in four different spellings; the
    /// same question is now asked one layer further out and must have the same answer.
    /// A pinch back to exactly 1× and a pan back to its origin are **still a live manipulation**
    /// — the fingers are down.
    @Test("liveness is presence, not magnitude")
    func presenceNotMagnitudeDecidesLiveness() throws {
        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: Self.viewport.center)
        manipulation.pinchChanged(to: 2)
        manipulation.panChanged(to: ViewPoint(x: 40, y: 40))

        manipulation.pinchChanged(to: 1)
        manipulation.panChanged(to: .zero)

        let gesture = try #require(manipulation.gesture(in: Self.viewport))

        #expect(gesture.isIdentity)
    }

    /// Totality before layout settles, matching `StageTransform.fitting`'s house rule: a
    /// viewport of zero must not produce a NaN anchor that then propagates into the transform.
    @Test("a zero viewport anchors at the centre")
    func aZeroViewportAnchorsAtTheCentre() throws {
        var manipulation = StageManipulation()
        manipulation.pinchBegan(scale: 1, centroid: ViewPoint(x: 120, y: 260))
        manipulation.pinchChanged(to: 2)

        let gesture = try #require(manipulation.gesture(in: .zero))

        #expect(gesture.anchorUnitX == 0.5)
        #expect(gesture.anchorUnitY == 0.5)
    }
}
