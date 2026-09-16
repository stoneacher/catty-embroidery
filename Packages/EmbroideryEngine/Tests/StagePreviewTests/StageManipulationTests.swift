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
        var first: ViewPoint
        var second: ViewPoint

        var centroid: ViewPoint {
            ViewPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
        }

        var separation: Double {
            let dx = second.x - first.x
            let dy = second.y - first.y
            return (dx * dx + dy * dy).squareRoot()
        }
    }

    /// Magnification limits wide enough never to bite, for the tests that are not about bounds.
    private static let free = StageManipulation.unlimitedMagnification

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
        let start = Fingers(first: ViewPoint(x: 100, y: 200), second: ViewPoint(x: 300, y: 400))
        let now = Fingers(first: ViewPoint(x: 140, y: 180), second: ViewPoint(x: 460, y: 500))
        let grabbedA = Self.fit.stagePoint(of: start.first)
        let grabbedB = Self.fit.stagePoint(of: start.second)

        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: start.centroid, within: Self.free)
        manipulation.panChanged(to: Self.delta(from: start.centroid, to: now.centroid))
        manipulation.pinchChanged(to: now.separation / start.separation)

        let gesture = try #require(manipulation.gesture(in: Self.viewport))
        let transform = Self.transform(for: gesture)

        #expect(Self.isClose(transform.viewPoint(of: grabbedA), now.first))
        #expect(Self.isClose(transform.viewPoint(of: grabbedB), now.second))
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
        manipulation.pinchBegan(scale: 1, centroid: centroid, within: Self.free)
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
        let start = Fingers(first: ViewPoint(x: 100, y: 240), second: ViewPoint(x: 300, y: 240))
        let sideways = ViewPoint(x: 90, y: -35)
        let now = Fingers(
            first: ViewPoint(x: start.first.x + sideways.x, y: start.first.y + sideways.y),
            second: ViewPoint(x: start.second.x + sideways.x, y: start.second.y + sideways.y)
        )

        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: start.centroid, within: Self.free)
        manipulation.panChanged(to: Self.delta(from: start.centroid, to: now.centroid))
        manipulation.pinchChanged(to: now.separation / start.separation)

        let gesture = try #require(manipulation.gesture(in: Self.viewport))
        let transform = Self.transform(for: gesture)

        // Asked of two grabbed points rather than by comparing the transform to
        // `fit.dragged(by: sideways)`. A pinch of exactly 1× still runs the composition, and
        // `pinched(by:about:)` re-derives the translation through a divide and a multiply — so
        // an exact comparison is a bet on a round trip landing on the same bits, which is the
        // one-ULP hazard ADR-028's Codex round 5 already lost once. Two points also say
        // something the transform equality does not: the stage *translated* rather than
        // scaling about a point that happens to move it there.
        for grabbed in [start.first, start.second].map(Self.fit.stagePoint(of:)) {
            let before = Self.fit.viewPoint(of: grabbed)
            #expect(Self.isClose(
                transform.viewPoint(of: grabbed),
                ViewPoint(x: before.x + sideways.x, y: before.y + sideways.y)
            ))
        }
    }

    /// ADR-028's correctness clause, re-established across the new input path: recogniser values
    /// are cumulative from the gesture's start, so folding each callback in as a delta compounds
    /// it — 2, 2, 2 would land at 8× for fingers that only ever asked for 2×.
    @Test("the magnification is cumulative, never accumulated")
    func theMagnificationIsCumulativeNeverAccumulated() throws {
        var manipulation = StageManipulation()
        manipulation.pinchBegan(scale: 1, centroid: Self.viewport.center, within: Self.free)
        manipulation.pinchChanged(to: 2)
        manipulation.pinchChanged(to: 2)
        manipulation.pinchChanged(to: 2)

        let gesture = try #require(manipulation.gesture(in: Self.viewport))

        #expect(gesture.magnification == 2)
    }

    // MARK: - More than one pinch in one manipulation

    /// **Lift one finger, put it back, never lifting the other.** The pan carries on throughout
    /// with `maximumNumberOfTouches = 2`, so this is one manipulation containing *two* pinches —
    /// and it is the ordinary way a two-finger gesture is adjusted, not an edge case.
    ///
    /// `UIPinchGestureRecognizer.scale` is cumulative from its own begin, and a coordinator
    /// resets it to 1 at `.began`, so the second pinch reports 1 where the manipulation is
    /// already at `m`. Taking that as the magnification snaps the stage back to unzoomed the
    /// instant the second finger lands.
    @Test("a second pinch during one pan does not reset the magnification")
    func aSecondPinchDuringOnePanDoesNotResetTheMagnification() throws {
        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: ViewPoint(x: 200, y: 300), within: Self.free)
        manipulation.pinchChanged(to: 3)
        manipulation.pinchEnded()
        manipulation.panChanged(to: ViewPoint(x: 20, y: 10))

        manipulation.pinchBegan(scale: 1, centroid: ViewPoint(x: 240, y: 280), within: Self.free)
        let gesture = try #require(manipulation.gesture(in: Self.viewport))

        #expect(gesture.magnification == 3)
    }

    /// And the frame must not move at the moment that second finger lands. Re-anchoring on the
    /// new centroid changes the composition even when the scale does not: the stage jumps by
    /// `(1 − m)(aNew − aOld)`, which is zero only when unzoomed or when the fingers land back on
    /// the old anchor.
    @Test("a second pinch during one pan does not move the stage")
    func aSecondPinchDuringOnePanDoesNotMoveTheStage() throws {
        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: ViewPoint(x: 200, y: 300), within: Self.free)
        manipulation.pinchChanged(to: 3)
        manipulation.pinchEnded()
        manipulation.panChanged(to: ViewPoint(x: 20, y: 10))

        let before = try #require(manipulation.gesture(in: Self.viewport))
        manipulation.pinchBegan(scale: 1, centroid: ViewPoint(x: 240, y: 280), within: Self.free)
        let after = try #require(manipulation.gesture(in: Self.viewport))

        // Observed at probe points rather than by comparing the transforms: the rebase re-derives
        // the translation through a divide and a multiply, so the two land two ULPs apart
        // (205.0 against 205.00000000000006) while describing the same frame. Asserting equality
        // here would be the same bet `lateralCentroidMovementDuringAPinchMovesTheStage` already
        // lost — and what matters is that nothing on screen moved, which is a claim about points.
        let (old, new) = (Self.transform(for: before), Self.transform(for: after))
        let corners = [ViewPoint(x: 0, y: 0), ViewPoint(x: 390, y: 500), ViewPoint(x: 240, y: 280)]
        for probe in corners.map(old.stagePoint(of:)) {
            #expect(Self.isClose(new.viewPoint(of: probe), old.viewPoint(of: probe), within: 1e-8))
        }
    }

    /// Having re-anchored without moving anything, the second pinch must then scale about the
    /// point the fingers are actually on — otherwise continuity was bought by zooming about a
    /// stale centroid the user has since left.
    @Test("a second pinch scales about the new fingers")
    func aSecondPinchScalesAboutTheNewFingers() throws {
        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: ViewPoint(x: 200, y: 300), within: Self.free)
        manipulation.pinchChanged(to: 3)
        manipulation.pinchEnded()
        manipulation.panChanged(to: ViewPoint(x: 20, y: 10))

        let regrasp = ViewPoint(x: 240, y: 280)
        let held = try #require(manipulation.gesture(in: Self.viewport))
        // The stage point sitting under the new centroid at the moment the fingers land.
        let grabbed = Self.transform(for: held).stagePoint(of: regrasp)

        manipulation.pinchBegan(scale: 1, centroid: regrasp, within: Self.free)
        manipulation.pinchChanged(to: 2)
        let zoomed = try #require(manipulation.gesture(in: Self.viewport))

        #expect(zoomed.magnification == 6)
        #expect(Self.isClose(Self.transform(for: zoomed).viewPoint(of: grabbed), regrasp, within: 1e-8))
    }

    /// **The rebase must compensate for the factor the transform actually applies, not the one
    /// the fingers asked for.** `StageTransform.pinched` clamps `baseline.scale × factor` into
    /// `StageZoomBounds`, so at a bound the effective factor is
    /// `clamp(s × requested) / s`, and a compensation computed from `requested` overshoots.
    ///
    /// Easily reached in ordinary use, which is why this is not an exotic case: the floor is
    /// `min(fit.scale, 0.05)`, so pinching a fitted design down a few times parks the
    /// manipulation on the bound with a finger still down. Found by `/codex-review` round 1.
    @Test("a rebase after a clamped pinch does not move the stage")
    func aRebaseAfterAClampedPinchDoesNotMoveTheStage() throws {
        // A fit near the ceiling, so a 3× pinch clamps to 2× and the two factors differ.
        let fit = StageTransform(scale: 25)
        let limits = StageInteraction().magnificationLimits(fitting: fit)
        let staged = { (gesture: StageGesture) in
            StageInteraction().transform(with: gesture, fitting: fit, in: Self.viewport)
        }

        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: ViewPoint(x: 100, y: 100), within: limits)
        manipulation.pinchChanged(to: 3)
        manipulation.pinchEnded()

        let clamped = try #require(manipulation.gesture(in: Self.viewport))
        #expect(clamped.magnification == 2, "the tracker holds what the transform will apply")

        let before = staged(clamped)
        manipulation.pinchBegan(scale: 1, centroid: ViewPoint(x: 200, y: 100), within: limits)
        let after = staged(try #require(manipulation.gesture(in: Self.viewport)))

        let corners = [ViewPoint(x: 0, y: 0), ViewPoint(x: 390, y: 500), ViewPoint(x: 200, y: 100)]
        for probe in corners.map(before.stagePoint(of:)) {
            #expect(Self.isClose(after.viewPoint(of: probe), before.viewPoint(of: probe), within: 1e-8))
        }

        // And the next pinch composes from what is displayed, not from the unclamped request.
        manipulation.pinchChanged(to: 0.5)
        let reduced = try #require(manipulation.gesture(in: Self.viewport))
        #expect(reduced.magnification == 1)
    }
}
