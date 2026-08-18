import EmbroideryEngine
import StagePreview
import Testing

/// US-307 criterion 8's arithmetic: the view-space similarity that carries one transform's
/// rendering onto another's, which is what makes the double-tap-to-fit reset animatable at
/// all.
///
/// **Every assertion here is differential.** The delta is checked by mapping stage points
/// through it and comparing against the destination transform's own `viewPoint(of:)` — never
/// against a second spelling of the delta's formula, which would stay correct only until
/// someone changed one of the two. That is the discipline `mapsFinitely` follows by calling
/// `viewPoint(of:)` instead of re-deriving it, and the reason US-302's round 7 asked for it.
@Suite("View delta")
struct ViewDeltaTests {
    private static let viewport = ViewSize(width: 390, height: 500)

    private static let probes = [
        StagePoint(x: 0, y: 0),
        StagePoint(x: 250, y: 250),
        StagePoint(x: -250, y: -250),
        StagePoint(x: 17.5, y: -3.25),
        StagePoint(x: -840, y: 1200)
    ]

    /// The defining property, over a spread of scale-and-translation pairs: applying the
    /// delta to where `from` puts a stage point lands exactly where `to` puts it.
    ///
    /// If this holds for five points spanning the stage and beyond it, the delta *is* the
    /// composition — two similarities agreeing on three non-collinear points are equal.
    @Test("the delta maps every point of the source rendering onto the destination's")
    func theDeltaMapsSourceOntoDestination() throws {
        let pairs: [(StageTransform, StageTransform)] = [
            (StageTransform(scale: 1), StageTransform(scale: 1)),
            (
                StageTransform(scale: 0.6, translation: ViewPoint(x: 195, y: 250)),
                StageTransform(scale: 3.2, translation: ViewPoint(x: -40, y: 88))
            ),
            (
                StageTransform(scale: 12, translation: ViewPoint(x: -900, y: 1400)),
                StageTransform(scale: 0.05, translation: ViewPoint(x: 12, y: -7.5))
            ),
            (
                StageTransform(scale: 0.05, translation: .zero),
                StageTransform(scale: 50, translation: ViewPoint(x: 3, y: 4))
            )
        ]

        for (from, to) in pairs {
            let delta = try #require(from.viewDelta(to: to, in: Self.viewport))
            for probe in Self.probes {
                let blitted = delta.apply(to: from.viewPoint(of: probe), in: Self.viewport)
                let restroked = to.viewPoint(of: probe)
                #expect(abs(blitted.x - restroked.x) < 1e-6, "x at \(probe) for \(from) → \(to)")
                #expect(abs(blitted.y - restroked.y) < 1e-6, "y at \(probe) for \(from) → \(to)")
            }
        }
    }

    /// **The flip cancels, and that is a derived fact worth its own test.** Both transforms
    /// apply `flippingY`, so the delta between them is a *positive* uniform scale in y-down
    /// view space. A delta that had inherited one flip would map the design mirrored — and
    /// the differential test above would catch it, but not say what went wrong.
    @Test("the delta carries no y-flip, so its scale is positive")
    func theDeltaCarriesNoYFlip() throws {
        let from = StageTransform(scale: 0.6, translation: ViewPoint(x: 195, y: 250))
        let to = StageTransform(scale: 2.4, translation: ViewPoint(x: 100, y: 100))

        let delta = try #require(from.viewDelta(to: to, in: Self.viewport))

        #expect(delta.scale > 0)
        #expect(abs(delta.scale - to.scale / from.scale) < 1e-12)
    }

    @Test("the delta from a transform to itself is the identity")
    func theDeltaToItselfIsTheIdentity() throws {
        let transform = StageTransform(scale: 1.75, translation: ViewPoint(x: -12, y: 34))

        let delta = try #require(transform.viewDelta(to: transform, in: Self.viewport))

        #expect(abs(delta.scale - 1) < 1e-12)
        #expect(abs(delta.translation.x) < 1e-9)
        #expect(abs(delta.translation.y) < 1e-9)
    }

    /// `.identity` must actually be the identity *through `apply`*, not merely look like it:
    /// it is what the animation channel holds when no gesture and no reset is in flight, so
    /// a sign error in `apply`'s anchor arithmetic would displace the whole canvas at rest.
    @Test("the identity delta moves nothing")
    func theIdentityMovesNothing() {
        for probe in Self.probes {
            let point = ViewPoint(x: probe.x, y: probe.y)
            let mapped = ViewDelta.identity.apply(to: point, in: Self.viewport)

            #expect(mapped == point)
        }
    }

    /// A degenerate viewport is reachable before layout settles, and `StageTransform.fitting`
    /// is already total for it. The delta must be too — a `nil` here would merely skip an
    /// animation, but a NaN would poison the canvas's effect modifiers.
    @Test("a zero viewport still yields a usable delta")
    func aZeroViewportStillYieldsADelta() throws {
        let from = StageTransform(scale: 1)
        let to = StageTransform(scale: 2, translation: ViewPoint(x: 5, y: 5))

        let delta = try #require(from.viewDelta(to: to, in: .zero))

        #expect(delta.scale.isFinite)
        #expect(delta.translation.x.isFinite)
        #expect(delta.translation.y.isFinite)
    }

    /// **Refused rather than collapsed to the identity**, for the reason `pinched` refuses:
    /// an identity delta would draw the source's pixels where they already are and report
    /// success, so the animation would visibly start from the wrong place. `nil` lets the
    /// caller swap the transform without animating, which is always correct.
    @Test("an unrepresentable delta is refused")
    func anUnrepresentableDeltaIsRefused() {
        let from = StageTransform(
            scale: StageTransform.minimumRepresentableScale,
            translation: ViewPoint(x: .greatestFiniteMagnitude, y: 0)
        )
        let to = StageTransform(scale: StageTransform.maximumScale)

        #expect(from.viewDelta(to: to, in: Self.viewport) == nil)
    }
}
