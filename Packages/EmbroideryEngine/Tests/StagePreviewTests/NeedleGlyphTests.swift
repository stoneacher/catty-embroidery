import EmbroideryEngine
import Foundation
import StagePreview
import Testing

/// The needle indicator's geometry, and specifically that it points where the machine
/// is about to go.
///
/// This lives in the package rather than the app for the reason `StitchDrawPlan` does:
/// the ADR-007 heading convention is arithmetic, and arithmetic belongs on the fast
/// `swift test` gate instead of behind a simulator boot and a screenshot.
@Suite("Needle glyph")
struct NeedleGlyphTests {
    /// Tip minus the midpoint of the shoulders, normalised — the direction the glyph
    /// visually points.
    private static func forwardDirection(of outline: [ViewPoint]) -> (x: Double, y: Double) {
        let tip = outline[0]
        let shoulderMidpoint = ViewPoint(
            x: (outline[1].x + outline[3].x) / 2,
            y: (outline[1].y + outline[3].y) / 2
        )
        let vector = (x: tip.x - shoulderMidpoint.x, y: tip.y - shoulderMidpoint.y)
        let length = (vector.x * vector.x + vector.y * vector.y).squareRoot()
        return (vector.x / length, vector.y / length)
    }

    /// **The test that cannot rot**, and the reason it is differential rather than a
    /// table of expected coordinates.
    ///
    /// ADR-007 pins degrees with 0° = up, x via sin and y via cos; `StageTransform`
    /// applies one y-flip. Those two facts compose to "the engine's angle goes into the
    /// rotation matrix unmodified" — no negation, no 90° offset — which is exactly the
    /// kind of claim that is easy to assert wrongly and easy to *fix* wrongly. So
    /// instead of hard-coding where the glyph should point, this steps a stage point
    /// forward using the engine's own convention, maps both points through the real
    /// transform, and asserts the glyph agrees with the direction the needle actually
    /// moved. A sign error in either place fails it; a sign error in *both* would be a
    /// consistent renderer and not a bug.
    @Test("the glyph faces where the engine would step",
          arguments: [0.0, 45, 90, 135, 180, 225, 270, 315, 37.5, -30, 450])
    func theGlyphFacesWhereTheEngineWouldStep(_ heading: Double) throws {
        let transform = StageTransform.fitting(StageGeometry.box, in: ViewSize(width: 300, height: 300))
        let origin = StagePoint(x: 10, y: 20)
        // ADR-007's convention, spelled out here rather than borrowed, so the test does
        // not inherit the very mapping it is checking.
        let radians = heading * .pi / 180
        let stepped = StagePoint(x: origin.x + 10 * sin(radians), y: origin.y + 10 * cos(radians))

        let from = transform.viewPoint(of: origin)
        let to = transform.viewPoint(of: stepped)
        let stepLength = ((to.x - from.x) * (to.x - from.x) + (to.y - from.y) * (to.y - from.y))
            .squareRoot()
        let expected = (x: (to.x - from.x) / stepLength, y: (to.y - from.y) / stepLength)

        let outline = try #require(NeedleGlyph.outline(at: from, heading: heading))
        let actual = Self.forwardDirection(of: outline)

        #expect(abs(actual.x - expected.x) < 1e-9)
        #expect(abs(actual.y - expected.y) < 1e-9)
    }

    /// The tip sits exactly on the needle's position, not at the glyph's centroid.
    ///
    /// The coordinate is marked by a point rather than one the user has to infer, and
    /// the pixels the body covers are ones already stitched — permanent, and revealed
    /// again as soon as the needle moves. A centred glyph would hide the newest
    /// stitches, which are the ones being watched.
    @Test("the tip is the needle's position")
    func theTipIsTheNeedlesPosition() throws {
        let tip = ViewPoint(x: 42, y: 17)

        let outline = try #require(NeedleGlyph.outline(at: tip, heading: 123))

        #expect(outline[0] == tip)
    }

    /// Fixed in **view** points, which is what stops US-307's pinch-zoom growing it into
    /// something that reads as a very large stitch. The glyph's extent must be identical
    /// at every scale.
    @Test("the glyph is the same size at every zoom level", arguments: [0.25, 1.0, 4.0, 40.0])
    func theGlyphIsTheSameSizeAtEveryZoom(_ scale: Double) throws {
        let transform = StageTransform(scale: scale)
        let tip = transform.viewPoint(of: StagePoint(x: 5, y: 5))

        let outline = try #require(NeedleGlyph.outline(at: tip, heading: 0))
        let distances: [Double] = outline.map { vertex in
            let dx: Double = vertex.x - tip.x
            let dy: Double = vertex.y - tip.y
            return (dx * dx + dy * dy).squareRoot()
        }
        let span: Double = distances.max() ?? 0

        // The furthest vertex from the tip is a shoulder, at hypot(halfWidth, length).
        let halfWidth: Double = NeedleGlyph.halfWidth
        let length: Double = NeedleGlyph.length
        let expected: Double = (halfWidth * halfWidth + length * length).squareRoot()
        #expect(abs(span - expected) < 1e-9)
    }

    /// A non-finite position is reachable from a legal program — ADR-021 divergence #5
    /// lets a coordinate the stream rejects still reach the display trace, and
    /// `changeXBy` accumulates to infinity. The whole glyph is skipped, which is right
    /// here in a way it would not be for a batched stitch path: there is nothing else in
    /// this shape to lose.
    @Test("an unusable position or heading yields no glyph",
          arguments: [
              ViewPoint(x: .nan, y: 0),
              ViewPoint(x: 0, y: .infinity),
              ViewPoint(x: -.infinity, y: -.infinity)
          ])
    func anUnusablePositionYieldsNoGlyph(_ tip: ViewPoint) {
        #expect(NeedleGlyph.outline(at: tip, heading: 0) == nil)
    }

    /// A *finite* heading whose radian conversion overflows must still give finite geometry.
    ///
    /// `heading * .pi / 180` overflows to infinity near `.greatestFiniteMagnitude`, and
    /// `sin`/`cos` of infinity are NaN — so the finiteness guard passed and the function
    /// returned non-finite points, contradicting its own contract (Codex round 1). The normal
    /// interpreter path normalises headings, so only the public API was exposed.
    @Test("an extreme but finite heading still yields finite geometry",
          arguments: [Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude, 1e300, 1e17])
    func anExtremeFiniteHeadingStillYieldsFiniteGeometry(_ heading: Double) throws {
        let outline = try #require(NeedleGlyph.outline(at: ViewPoint(x: 5, y: 5), heading: heading))

        #expect(outline.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    /// Rotation is periodic, so reducing the angle must not change the glyph.
    @Test("headings a full turn apart produce the same glyph", arguments: [0.0, 37.5, 210])
    func headingsAFullTurnApartProduceTheSameGlyph(_ heading: Double) throws {
        let tip = ViewPoint(x: 3, y: 4)
        let base = try #require(NeedleGlyph.outline(at: tip, heading: heading))
        let wrapped = try #require(NeedleGlyph.outline(at: tip, heading: heading + 720))

        for (lhs, rhs) in zip(base, wrapped) {
            #expect(abs(lhs.x - rhs.x) < 1e-9)
            #expect(abs(lhs.y - rhs.y) < 1e-9)
        }
    }

    @Test("a non-finite heading yields no glyph")
    func aNonFiniteHeadingYieldsNoGlyph() {
        #expect(NeedleGlyph.outline(at: ViewPoint(x: 1, y: 1), heading: .nan) == nil)
        #expect(NeedleGlyph.outline(at: ViewPoint(x: 1, y: 1), heading: .infinity) == nil)
    }

    /// The notch is what makes this read as a dart pointing somewhere rather than as a
    /// plain cone, so it must sit between the tip and the shoulders.
    @Test("the trailing notch lies between the tip and the shoulders")
    func theNotchLiesBetweenTheTipAndTheShoulders() {
        #expect(NeedleGlyph.notchLength > 0)
        #expect(NeedleGlyph.notchLength < NeedleGlyph.length)
    }

    /// Increase Contrast is exactly the setting that undoes opacity and width, so it gets
    /// a wider halo rather than a colour change.
    @Test("increased contrast widens the halo")
    func increasedContrastWidensTheHalo() {
        #expect(NeedleGlyph.increasedContrastHaloWidth > NeedleGlyph.haloWidth)
    }
}
