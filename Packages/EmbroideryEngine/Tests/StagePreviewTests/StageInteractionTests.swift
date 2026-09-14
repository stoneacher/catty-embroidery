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

    // MARK: - What a manipulation does to the bake key (US-313a)

    /// **ADR-030 §7's inherited invariant, observed rather than restated.** US-310's rung works
    /// because `StageInteraction.settled` is not written while fingers are down: the bake key
    /// holds still, so the settled prefix is rasterised once per manipulation and every frame in
    /// between takes the coarse plan. A continuous commit would move the key per frame and
    /// re-rasterise 50 000 stitches every frame — worse than before US-310 existed.
    ///
    /// Driven through the real tracker rather than through hand-built `StageGesture`s, because
    /// what is being pinned is that *this input path* cannot move the key.
    @Test("the bake transform is unchanged for every frame of a manipulation")
    func theBakeTransformIsUnchangedForEveryFrameOfAManipulation() throws {
        var interaction = StageInteraction()
        interaction.commit(Self.pinch(1.4), fitting: Self.fit, in: Self.viewport)
        let committed = interaction.baseline(fitting: Self.fit)

        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        manipulation.pinchBegan(scale: 1, centroid: Self.viewport.center)

        var bakes: [StageTransform] = []
        var frames: [StageTransform] = []
        for step in 1 ... 8 {
            manipulation.panChanged(to: ViewPoint(x: Double(step) * 7, y: Double(step) * -3))
            manipulation.pinchChanged(to: 1 + Double(step) / 10)
            let gesture = try #require(manipulation.gesture(in: Self.viewport))
            let rendering = interaction.rendering(
                gesture: gesture, fitting: Self.fit, in: Self.viewport
            )
            bakes.append(rendering.bake)
            frames.append(rendering.current)
            #expect(!rendering.canUseRaster)
        }

        #expect(bakes.allSatisfy { $0 == committed })
        // The frame moved on every one of those steps, so the key holding still is a property of
        // the design and not of a manipulation that happened to do nothing.
        #expect(Set(frames).count == 8)

        manipulation.pinchEnded()
        manipulation.panEnded()
        // Bound before `#require`: the macro expands its argument into a closure, and `finish`
        // is `mutating`.
        let finished = manipulation.finish(in: Self.viewport)
        try interaction.commit(#require(finished), fitting: Self.fit, in: Self.viewport)

        #expect(interaction.rendering(gesture: nil, fitting: Self.fit, in: Self.viewport).bake
            != committed)
    }

    /// **Fingers down, nothing moved: still live — and this test asserts the opposite of what
    /// US-313a planned.**
    ///
    /// The plan resolved a disagreement between its two planning passes in favour of gating
    /// `.live` on `!gesture.isIdentity`, so the image would not degrade on a stationary frame at
    /// touch-down. The argument was that an unmoved gesture leaves the bake key where it is, so
    /// nothing could be re-baked. **It is wrong**, and `aGestureAtItsBaselineIsStillLive` above
    /// — written for ADR-028's Codex round 2 — caught it within a minute of the gate being
    /// implemented: `BakeKey` carries `settledCount` as well as the transform, and that advances
    /// while a run is still producing stitches. A resting frame that composites the raster
    /// mid-gesture therefore permits a bake at a *new* watermark, rasterising the settled prefix
    /// during the gesture at whatever the design has reached.
    ///
    /// Kept as the positive statement of the rule, in the terms US-313's tracker produces it:
    /// a manipulation with fingers down and nothing moved is live, and its bake key is the
    /// committed transform.
    @Test("a resting manipulation is live and keeps the committed transform as its bake key")
    func aRestingManipulationIsLive() throws {
        var interaction = StageInteraction()
        interaction.commit(Self.pinch(1.4), fitting: Self.fit, in: Self.viewport)
        let committed = interaction.baseline(fitting: Self.fit)

        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        let resting = try #require(manipulation.gesture(in: Self.viewport))
        let rendering = interaction.rendering(
            gesture: resting, fitting: Self.fit, in: Self.viewport
        )

        #expect(resting.isIdentity)
        #expect(!rendering.canUseRaster)
        #expect(rendering.bake == committed)
        #expect(rendering.current == committed, "an identity gesture draws exactly the baseline")
    }

    /// The consequence at the scale the rung was built for: **every** frame of a manipulation
    /// takes the coarse plan, including the ones where the fingers have not moved yet. That
    /// costs fidelity on a stationary frame, which the plan tried to avoid and could not — see
    /// `aRestingManipulationIsLive`. What it buys is that no bake can fire while fingers are
    /// down, which at 50 000 stitches is the expensive half of ADR-009.
    @Test("every frame of a manipulation draws the coarse plan, moved or not")
    func everyFrameOfAManipulationDrawsTheCoarsePlan() throws {
        let list = displayList(
            (0 ..< 50_001).map { previewStitch(Double($0) * 10, 0, PreviewColor.red) }
        )
        var interaction = StageInteraction()
        interaction.commit(Self.pinch(1.2), fitting: Self.fit, in: Self.viewport)

        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)

        for movement in [ViewPoint.zero, ViewPoint(x: 12, y: 4), ViewPoint(x: 40, y: 9)] {
            manipulation.panChanged(to: movement)
            let gesture = try #require(manipulation.gesture(in: Self.viewport))
            #expect(StitchDrawPlan.forFrame(
                of: list,
                at: interaction.rendering(gesture: gesture, fitting: Self.fit, in: Self.viewport),
                compositingRaster: true
            ) == StitchDrawPlan.coarse(of: list))
        }

        // And with no manipulation at all it is the live window again, so the coarse plan is
        // paid for only while fingers are down.
        #expect(StitchDrawPlan.forFrame(
            of: list,
            at: interaction.rendering(gesture: nil, fitting: Self.fit, in: Self.viewport),
            compositingRaster: true
        ) == StitchDrawPlan.live(of: list))
    }
}
