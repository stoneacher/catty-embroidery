import StagePreview
import Testing

/// The arithmetic behind the four directional pan accessibility actions.
///
/// **US-313a shipped `panned(by:)` and called the 25 % step tested; it is not.** That story's
/// AC12 says "a directional pan of ~25 % of the viewport, tested headlessly", but
/// `StageInteraction.panned(by:)` takes a raw delta and no fraction appears anywhere in the
/// package — so the number a user actually moves by lived only in the plan. It comes into the
/// package here, where `swift test` can ask, rather than being spelled four times in a view.
///
/// **The sign convention is the whole content of this suite**, because it is the half that makes
/// the feature feel inverted when it is wrong and cannot be seen in a screenshot. "Pan Left"
/// means the **viewport** moves left — more of the design's left-hand side becomes visible, and
/// the content therefore slides *right*. That is the convention every spoken or typed direction
/// uses ("scroll down" shows you what is further down; the arrow keys in Maps and Photos are
/// camera-relative). The opposite, content-relative reading exists only in gesture APIs, where
/// the user's own hand supplies the direction and no word is spoken. A named action is a word,
/// so it takes the word's convention. (Sebastian's decision, 2026-09-16.)
@Suite("Stage pan direction")
struct StagePanDirectionTests {
    /// Deliberately not square, so an implementation that uses one extent for both axes fails.
    private static let viewport = ViewSize(width: 400, height: 800)

    private static var fit: StageTransform {
        StageTransform.fitting(StageGeometry.box, in: viewport)
    }

    private static func isClose(_ actual: ViewPoint, _ expected: ViewPoint) -> Bool {
        abs(actual.x - expected.x) < 1e-9 && abs(actual.y - expected.y) < 1e-9
    }

    /// A quarter of *what the user can see*, which is why the step is a viewport fraction and
    /// carries no scale term: at 50× a quarter of the viewport covers a fiftieth of the stage
    /// distance it covers at the fit, so the step is zoom-adaptive by construction.
    @Test("the step is a quarter of the viewport, on the axis it names")
    func theStepIsAQuarterOfTheViewportOnItsOwnAxis() {
        #expect(StagePanDirection.accessibilityFraction == 0.25)

        #expect(Self.isClose(StagePanDirection.left.step(in: Self.viewport), ViewPoint(x: 100, y: 0)))
        #expect(Self.isClose(StagePanDirection.right.step(in: Self.viewport), ViewPoint(x: -100, y: 0)))
        #expect(Self.isClose(StagePanDirection.up.step(in: Self.viewport), ViewPoint(x: 0, y: 200)))
        #expect(Self.isClose(StagePanDirection.down.step(in: Self.viewport), ViewPoint(x: 0, y: -200)))
    }

    /// **The convention, asserted as a user would check it** rather than as a sign on a `Double`.
    ///
    /// A stage point sitting off the left edge of the viewport is invisible; after one "Pan Left"
    /// it must be *inside* the viewport, because panning left is how you go and look at it. An
    /// implementation with the sign inverted pushes it further off and fails here — which a test
    /// asserting `delta.x < 0` would not, since it would simply be asserting the mistake.
    @Test("panning left brings what was off the left edge into view")
    func panningLeftBringsWhatWasOffTheLeftEdgeIntoView() {
        var interaction = StageInteraction()
        // 50 pt off the left edge, vertically centred.
        let offscreen = Self.fit.stagePoint(of: ViewPoint(x: -50, y: 400))

        interaction.panned(
            by: StagePanDirection.left.step(in: Self.viewport), fitting: Self.fit
        )
        let now = interaction.baseline(fitting: Self.fit).viewPoint(of: offscreen)

        #expect(now.x > 0)
        #expect(now.x < Self.viewport.width)
    }

    /// The vertical half of the same claim, and the one the y-down convention can invert
    /// silently: `dragged(by:)` is pure view space, so a positive `y` moves the content *down*,
    /// which is what reveals what was above it.
    @Test("panning up brings what was off the top edge into view")
    func panningUpBringsWhatWasOffTheTopEdgeIntoView() {
        var interaction = StageInteraction()
        let offscreen = Self.fit.stagePoint(of: ViewPoint(x: 200, y: -100))

        interaction.panned(
            by: StagePanDirection.up.step(in: Self.viewport), fitting: Self.fit
        )
        let now = interaction.baseline(fitting: Self.fit).viewPoint(of: offscreen)

        #expect(now.y > 0)
        #expect(now.y < Self.viewport.height)
    }

    /// Opposite directions cancel exactly, so a user who over-shoots gets back to where they
    /// were rather than to somewhere near it. Not a rounding claim — the two deltas are the same
    /// magnitude by construction, and this is what says so.
    @Test("opposite directions cancel", arguments: [
        (StagePanDirection.left, StagePanDirection.right),
        (StagePanDirection.up, StagePanDirection.down)
    ])
    func oppositeDirectionsCancel(there: StagePanDirection, back: StagePanDirection) {
        var interaction = StageInteraction()
        let probe = Self.fit.stagePoint(of: Self.viewport.center)

        interaction.panned(by: there.step(in: Self.viewport), fitting: Self.fit)
        interaction.panned(by: back.step(in: Self.viewport), fitting: Self.fit)

        #expect(Self.isClose(
            interaction.baseline(fitting: Self.fit).viewPoint(of: probe), Self.viewport.center
        ))
    }

    /// Total for a viewport measured before layout settles — `StageTransform.fitting`'s house
    /// rule, which every other viewport divisor in this package follows. A zero viewport has no
    /// quarter to move by, and an action that fires during the first layout pass must be a
    /// no-op rather than a `NaN` that poisons the transform.
    @Test("a viewport measured before layout moves nothing")
    func aViewportMeasuredBeforeLayoutMovesNothing() {
        for direction in StagePanDirection.allCases {
            #expect(direction.step(in: .zero) == .zero)
        }
    }

    /// Four directions and no more.
    ///
    /// **Not because the view iterates them** — it writes four modifiers out by hand, because the
    /// order they are declared in is the order the Actions rotor offers them and "Fit to Hoop"
    /// has to stay first. An earlier version of this comment claimed the opposite, which had the
    /// consequence backwards: a fifth case would be silently *unreachable* in the UI rather than
    /// automatically offered (`swift-code-reviewer`, S8). What `CaseIterable` buys is this test
    /// and the app-side name mapping, where a fifth case is a compile error.
    @Test("there are exactly four directions")
    func thereAreExactlyFourDirections() {
        #expect(StagePanDirection.allCases.count == 4)
        #expect(Set(StagePanDirection.allCases).count == 4)
    }
}
