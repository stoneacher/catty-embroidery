import StagePreview
import Testing

/// **The interaction layer, tested for the first time.**
///
/// Every one of these properties was previously spread across a SwiftUI view and could only be
/// checked by reading it — which is why the cross-vendor review found a defect in it in six
/// consecutive rounds, four of them the same conceptual mistake. The regressions below are
/// named after the round that found them, so a future change that reintroduces one is told
/// which argument it is losing.
@Suite("Stage interaction")
struct StageInteractionTests {
    private static let viewport = ViewSize(width: 390, height: 500)

    private static var fit: StageTransform {
        StageTransform.fitting(StageGeometry.box, in: viewport)
    }

    /// The asymmetric fit whose re-derived translation lands one ULP away — Codex round 5's
    /// reproducer, kept because it is the only fixture that catches an equality-based guard.
    private static var asymmetricFit: StageTransform {
        StageTransform.fitting(
            StageGeometry.fitTarget(
                including: StageBox(
                    minX: -250, minY: -250, maxX: 2729.909673862173, maxY: 10178.013339079671
                )
            ),
            in: ViewSize(width: 390, height: 700)
        )
    }

    private static func pinch(_ magnification: Double) -> StageGesture {
        StageGesture(magnification: magnification)
    }

    private static func pan(x: Double, y: Double) -> StageGesture {
        StageGesture(panX: x, panY: y)
    }

    // MARK: - Following the fit

    @Test("a fresh interaction follows the fit and is not settling")
    func aFreshInteractionFollowsTheFit() {
        let interaction = StageInteraction()

        #expect(interaction.isFollowingFit)
        #expect(!interaction.isSettling)
        #expect(interaction.baseline(fitting: Self.fit) == Self.fit)
        #expect(interaction.rendering(gesture: nil, fitting: Self.fit, in: Self.viewport)
            == .settled(Self.fit))
    }

    @Test("following the fit means a changed viewport changes what is drawn")
    func followingTheFitRefits() {
        let interaction = StageInteraction()
        let narrow = StageTransform.fitting(StageGeometry.box, in: ViewSize(width: 200, height: 200))

        #expect(interaction.baseline(fitting: narrow) == narrow)
        #expect(interaction.baseline(fitting: narrow) != interaction.baseline(fitting: Self.fit))
    }

    // MARK: - The lifecycle question, asked four wrong ways before

    /// Round 2's defect: a gesture returned to its baseline reported "settled" and let the
    /// raster rebuild mid-gesture. Liveness is the gesture's *presence*, not its value.
    @Test("a gesture at its baseline is still live")
    func aGestureAtItsBaselineIsStillLive() {
        let interaction = StageInteraction()

        let rendering = interaction.rendering(
            gesture: Self.pinch(1), fitting: Self.fit, in: Self.viewport
        )

        #expect(!rendering.canUseRaster, "a gesture in flight must not composite the raster")
        #expect(rendering.bake == Self.fit)
        #expect(rendering.current == Self.fit, "an identity gesture draws exactly the baseline")
    }

    /// Round 3's defect, in the form the enum now makes unrepresentable: a pinch taken out and
    /// back is an identity *value* and a live *gesture*, and only the second decides rendering.
    @Test("only the gesture's presence decides liveness, never its magnitude")
    func presenceNotMagnitudeDecidesLiveness() {
        let interaction = StageInteraction()

        for magnification in [0.5, 1.0, 2.0] {
            let live = interaction.rendering(
                gesture: Self.pinch(magnification), fitting: Self.fit, in: Self.viewport
            )
            #expect(!live.canUseRaster, "magnification \(magnification) must still be live")
        }
        #expect(
            interaction.rendering(gesture: nil, fitting: Self.fit, in: Self.viewport).canUseRaster
        )
    }

    // MARK: - Commit

    /// Rounds 4 and 5: a gesture that did nothing must not take the stage off the fit — checked
    /// against the asymmetric fit, where comparing transforms would say they differ.
    @Test("an identity gesture never takes the stage off the fit")
    func anIdentityGestureKeepsFollowingTheFit() {
        for fit in [Self.fit, Self.asymmetricFit] {
            var interaction = StageInteraction()

            interaction.commit(Self.pinch(1), fitting: fit, in: Self.viewport)

            #expect(interaction.isFollowingFit)
        }
    }

    @Test("an identity gesture leaves an explicit transform explicit")
    func anIdentityGestureKeepsAnExplicitTransform() {
        var interaction = StageInteraction()
        interaction.commit(Self.pinch(3), fitting: Self.fit, in: Self.viewport)
        let zoomed = interaction.baseline(fitting: Self.fit)

        interaction.commit(Self.pinch(1), fitting: Self.fit, in: Self.viewport)

        #expect(!interaction.isFollowingFit)
        #expect(interaction.baseline(fitting: Self.fit) == zoomed)
    }

    /// **What the frame showed is what the user gets.** The disagreement this forbids shipped
    /// twice on this branch — once by a threshold subtracted live and not at commit, once by a
    /// single ULP — so it is asserted over a spread rather than one case.
    @Test("the last frame of a gesture is exactly what committing it produces")
    func thePreviewedFrameIsWhatCommits() {
        let gestures = [
            Self.pinch(1),
            Self.pinch(2.5),
            Self.pan(x: -60, y: 40),
            StageGesture(magnification: 0.4, anchorUnitX: 0.1, anchorUnitY: 0.9, panX: 200, panY: -150),
            StageGesture(magnification: 1e6, panX: 5, panY: 5)
        ]

        for fit in [Self.fit, Self.asymmetricFit] {
            for gesture in gestures {
                var interaction = StageInteraction()
                let previewed = interaction.transform(
                    with: gesture, fitting: fit, in: Self.viewport
                )

                interaction.commit(gesture, fitting: fit, in: Self.viewport)

                #expect(
                    interaction.baseline(fitting: fit) == previewed,
                    "preview and commit disagree for \(gesture)"
                )
            }
        }
    }

    /// Previewing is pure: drawing a frame must not move the stage, or a gesture would compound
    /// against itself once per frame.
    @Test("previewing a gesture never mutates the interaction")
    func previewingDoesNotMutate() {
        var interaction = StageInteraction()
        interaction.commit(Self.pinch(2), fitting: Self.fit, in: Self.viewport)
        let before = interaction

        for _ in 0 ..< 10 {
            _ = interaction.transform(with: Self.pinch(3), fitting: Self.fit, in: Self.viewport)
        }

        #expect(interaction == before)
    }
}
