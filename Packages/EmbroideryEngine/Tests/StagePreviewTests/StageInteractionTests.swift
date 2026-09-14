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

    /// **Fingers down, nothing moved: draw the cached raster.**
    ///
    /// `rendering` used to go `.live` the instant a gesture existed, so the image degraded at
    /// touch-down — a fidelity pop on a *stationary* frame, which is the most visible kind. It is
    /// safe to keep the settled path here for the reason the invariant exists: the bake key is
    /// still the committed transform, so this frame composites a raster that is already correct,
    /// and nothing is re-baked. The pop moves to first movement, where motion masks it.
    ///
    /// `swift-architect` proposed asserting `canUseRaster == false` for *every* frame of a
    /// manipulation, which would forbid this; `swift-ui-design` proposed the gate. The
    /// invariant that actually matters is the one above — the key does not move — and this test
    /// and the previous one pin it together.
    @Test("an identity gesture renders from the settled path and leaves the bake key alone")
    func anIdentityGestureRendersFromTheSettledPath() throws {
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
        #expect(rendering == .settled(committed))
        #expect(rendering.canUseRaster)
    }

    /// The consequence at the scale the rung was built for: a moved frame takes the coarse plan,
    /// a resting one does not pay for coarseness it does not need.
    @Test("a moved frame draws the coarse plan and a resting frame draws the live one")
    func aMovedFrameDrawsTheCoarsePlan() throws {
        let list = displayList(
            (0 ..< 50001).map { previewStitch(Double($0) * 10, 0, PreviewColor.red) }
        )
        var interaction = StageInteraction()
        interaction.commit(Self.pinch(1.2), fitting: Self.fit, in: Self.viewport)

        var manipulation = StageManipulation()
        manipulation.panBegan(at: .zero)
        let resting = try #require(manipulation.gesture(in: Self.viewport))
        #expect(StitchDrawPlan.forFrame(
            of: list,
            at: interaction.rendering(gesture: resting, fitting: Self.fit, in: Self.viewport),
            compositingRaster: true
        ) == StitchDrawPlan.live(of: list))

        manipulation.panChanged(to: ViewPoint(x: 12, y: 4))
        let moved = try #require(manipulation.gesture(in: Self.viewport))
        #expect(StitchDrawPlan.forFrame(
            of: list,
            at: interaction.rendering(gesture: moved, fitting: Self.fit, in: Self.viewport),
            compositingRaster: true
        ) == StitchDrawPlan.coarse(of: list))
    }
}
