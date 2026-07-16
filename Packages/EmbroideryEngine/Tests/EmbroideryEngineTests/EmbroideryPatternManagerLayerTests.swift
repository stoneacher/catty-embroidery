import EmbroideryEngine
import Testing

@Suite("EmbroideryPatternManager layer switching and assembly")
struct EmbroideryPatternManagerLayerTests {
    private let actor = ActorID(0)
    private let otherActor = ActorID(1)

    // MARK: - Clause thresholds (US-110; clauses B, C, and D)

    @Test("Clause B at a +60.75-stage gap arms no jump, yet the replay interpolates")
    func actorChangeAtPositiveHalfUnitGap() {
        // Codex US-110 round-1 blind spot: the ±60.75 asymmetry was pinned
        // only through clauses C/D. Clause B rounds prev − target =
        // round(−121.5) = −121 → not far, so no jump between its two
        // workspace emissions — while the stream's replay rounds target −
        // previous = 122 and interpolates the move to the target.
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: 60.75, y: 0), layer: 0, actor: otherActor)

        let stream = manager.assembled()
        let origin = EmbroideryPoint(x: 0, y: 0)
        #expect(stream.stitches.map(\.position) == [
            origin,
            origin, // clause B, color change
            origin, // clause B, no jump — the gap is clause-near
            origin, // interpolation: duplicate-of-previous
            EmbroideryPoint(x: 60, y: 0), // interpolation: intermediate
            EmbroideryPoint(x: 122, y: 0), // interpolation: target as jump
            EmbroideryPoint(x: 122, y: 0) // plain target
        ])
        #expect(stream.stitches.map(\.isColorChange) == [
            false, true, false, false, false, false, false
        ])
        #expect(stream.stitches.map(\.isJump) == [
            false, false, false, true, true, true, false
        ])
        #expect(stream.colorChangeCount == 1)
    }

    @Test("Clause B at a −60.75-stage gap arms the jump, yet the replay does not interpolate")
    func actorChangeAtNegativeHalfUnitGap() {
        // Mirror direction: prev − target = round(121.5) = 122 → far, the
        // second workspace emission is a jump — while the replay rounds
        // −121.5 to −121 and appends the target without interpolation.
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: -60.75, y: 0), layer: 0, actor: otherActor)

        let stream = manager.assembled()
        let origin = EmbroideryPoint(x: 0, y: 0)
        #expect(stream.stitches.map(\.position) == [
            origin,
            origin, // clause B, color change
            origin, // clause B, jump — the gap is clause-far
            EmbroideryPoint(x: -121, y: 0) // plain target, no interpolation
        ])
        #expect(stream.stitches.map(\.isColorChange) == [false, true, false, false])
        #expect(stream.stitches.map(\.isJump) == [false, false, true, false])
        #expect(stream.colorChangeCount == 1)
    }

    @Test("An actor change and the actor's own layer switch compose — clauses B and D together")
    func actorChangeComposesWithLayerEntry() {
        // Codex US-110 round-1 blind spot: actor B stitched on layer 1,
        // actor A stitched on layer 0, then B enters layer 0. Catroid runs
        // both the actor-change transition (B: change + workspace point
        // twice) and B's previous-layer connecting emission (D), before the
        // target (E).
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 5, y: 5), layer: 1, actor: otherActor)
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: 6, y: 6), layer: 0, actor: otherActor)

        let stream = manager.assembled()
        let origin = EmbroideryPoint(x: 0, y: 0)
        #expect(stream.stitches.map(\.position) == [
            origin, // layer 0: actor A
            origin, // clause B, color change
            origin, // clause B, emitted again
            EmbroideryPoint(x: 10, y: 10), // clause D: B's previous-layer point
            EmbroideryPoint(x: 12, y: 12), // clause E target
            EmbroideryPoint(x: 12, y: 12), // boundary color change
            EmbroideryPoint(x: 12, y: 12), // join jump
            EmbroideryPoint(x: 10, y: 10) // layer 1: B's first command
        ])
        #expect(stream.stitches.map(\.isColorChange) == [
            false, true, false, false, false, true, false, false
        ])
        #expect(stream.stitches.map(\.isJump) == [
            false, false, false, false, false, false, true, false
        ])
        #expect(stream.colorChangeCount == 2)
    }

    // MARK: - Layer-switch thresholds (US-110; clauses C and D)

    @Test("At exactly 121 units a layer switch ties off — clause C else, clause D skips")
    func layerSwitchAtExactThreshold() {
        // Catroid compares with strict `>` in clause C and strict `<` in
        // clause D: a 121-unit gap (stage 60.5 × 2) takes C's tie-off branch
        // (prev, jump, prev) and D emits nothing.
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 1, actor: actor)
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: 60.5, y: 0), layer: 1, actor: actor)

        let stream = manager.assembled()
        let origin = EmbroideryPoint(x: 0, y: 0)
        #expect(stream.stitches.map(\.position) == [
            origin, origin, // layer 0: clause D + E of the second command
            origin, // boundary color change
            origin, // join jump
            origin, // layer 1: first command
            origin, origin, // clause C tie-off: prev (change), prev (jump)
            EmbroideryPoint(x: 121, y: 0) // clause E target, no interpolation
        ])
        #expect(stream.stitches.map(\.isColorChange) == [
            false, false, true, false, false, true, false, false
        ])
        #expect(stream.stitches.map(\.isJump) == [
            false, false, false, true, false, false, true, false
        ])
        #expect(stream.colorChangeCount == 2)
    }

    @Test("Past 121 units a layer switch emits the target twice — clause C then-branch")
    func layerSwitchPastThreshold() {
        // 122 units: clause C emits the target once with the color change
        // armed, clause D skips, clause E emits the target again. On replay
        // the armed change rides out the interpolation and lands on the
        // final plain stitch (ADR-013).
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 1, actor: actor)
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: 61, y: 0), layer: 1, actor: actor)

        let stream = manager.assembled()
        let origin = EmbroideryPoint(x: 0, y: 0)
        #expect(stream.stitches.map(\.position) == [
            origin, origin, // layer 0: clause D + E
            origin, // boundary color change
            origin, // join jump
            origin, // layer 1: first command
            origin, // interpolation: duplicate-of-previous
            EmbroideryPoint(x: 62, y: 0), // interpolation: intermediate (stage 30.5 javaRounds to 31)
            EmbroideryPoint(x: 122, y: 0), // interpolation: target as jump
            EmbroideryPoint(x: 122, y: 0), // plain target, carries the change (ADR-013)
            EmbroideryPoint(x: 122, y: 0) // clause E duplicate
        ])
        #expect(stream.stitches.map(\.isColorChange) == [
            false, false, true, false, false, false, false, false, true, false
        ])
        #expect(stream.stitches.map(\.isJump) == [
            false, false, false, true, false, true, true, true, false, false
        ])
        #expect(stream.colorChangeCount == 2)
    }

    @Test("A +60.75-stage layer-switch gap is near — clause distance rounds previous minus target")
    func layerSwitchPositiveHalfUnitGapIsNear() {
        // swift-code-reviewer US-110 find: Catroid's act clauses compute
        // `getMaxDistanceBetweenPoints(prev, target)` = round((prev − target)
        // × 2), and `javaRound` is asymmetric at negative halves — so a
        // +60.75 stage gap is round(−121.5) = −121 → near (clause C ties
        // off, D skips), while the *stream's* interpolation check rounds
        // target − previous = 122 → the tie-off is followed by an
        // interpolated move. Rounding target − previous in the clauses
        // would misclassify this as far.
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 1, actor: actor)
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: 60.75, y: 0), layer: 1, actor: actor)

        let stream = manager.assembled()
        let origin = EmbroideryPoint(x: 0, y: 0)
        #expect(stream.stitches.map(\.position) == [
            origin, origin, // layer 0: clause D + E
            origin, // boundary color change
            origin, // join jump
            origin, // layer 1: first command
            origin, origin, // clause C tie-off: prev (change), prev (jump)
            origin, // interpolation: duplicate-of-previous
            EmbroideryPoint(x: 60, y: 0), // interpolation: intermediate (stage 30.375 javaRounds to 30)
            EmbroideryPoint(x: 122, y: 0), // interpolation: target as jump
            EmbroideryPoint(x: 122, y: 0) // plain target
        ])
        #expect(stream.stitches.map(\.isColorChange) == [
            false, false, true, false, false, true, false, false, false, false, false
        ])
        #expect(stream.stitches.map(\.isJump) == [
            false, false, false, true, false, false, true, true, true, true, false
        ])
        #expect(stream.colorChangeCount == 2)
    }

    @Test("A −60.75-stage layer-switch gap is far — the mirror direction classifies asymmetrically")
    func layerSwitchNegativeHalfUnitGapIsFar() {
        // Mirror of the +60.75 case: prev − target = +121.5 rounds to 122 →
        // far (clause C emits the target with the change, E repeats it),
        // while the stream's interpolation check rounds −121.5 to −121 →
        // no interpolation. The two directions must not behave alike.
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 1, actor: actor)
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: -60.75, y: 0), layer: 1, actor: actor)

        let stream = manager.assembled()
        let origin = EmbroideryPoint(x: 0, y: 0)
        #expect(stream.stitches.map(\.position) == [
            origin, origin, // layer 0: clause D + E
            origin, // boundary color change
            origin, // join jump
            origin, // layer 1: first command
            EmbroideryPoint(x: -121, y: 0), // clause C far branch: target with the change
            EmbroideryPoint(x: -121, y: 0) // clause E duplicate
        ])
        #expect(stream.stitches.map(\.isColorChange) == [
            false, false, true, false, false, true, false
        ])
        #expect(stream.stitches.map(\.isJump) == [
            false, false, false, true, false, false, false
        ])
        #expect(stream.colorChangeCount == 2)
    }

    // MARK: - Layer assembly (US-110; port of DSTPatternManager)

    @Test("An empty manager assembles to an empty stream")
    func emptyManager() {
        let manager = EmbroideryPatternManager()
        let stream = manager.assembled()
        #expect(stream.stitches.isEmpty)
        #expect(stream.colorChangeCount == 0)
        #expect(!manager.hasValidPattern)
    }

    @Test("A single command yields one stitch and no valid pattern")
    func singleCommand() {
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 5, y: 5), layer: 0, actor: actor)

        let stream = manager.assembled()
        #expect(stream.stitches.map(\.position) == [EmbroideryPoint(x: 10, y: 10)])
        #expect(stream.stitches.map(\.isJump) == [false])
        #expect(stream.stitches.map(\.isColorChange) == [false])
        // Catroid `validPatternExists` needs more than one point.
        #expect(!manager.hasValidPattern)

        manager.addStitch(at: StagePoint(x: 6, y: 6), layer: 0, actor: actor)
        #expect(manager.hasValidPattern)
    }

    @Test("Two same-position commands across layers assemble to five points")
    func fivePointGolden() {
        // Port of DSTPatternManagerTest.testMultilayerEmbroideryPatternList:
        // (0,0) on layer 0 and layer 1 → layer 0 [P], layer 1 [P, P] (clause
        // D + E), assembled P, P(change), P(jump), P, P.
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 1, actor: actor)

        let stream = manager.assembled()
        #expect(stream.stitches.count == 5)
        #expect(stream.stitches.allSatisfy { $0.position == EmbroideryPoint(x: 0, y: 0) })
        #expect(stream.stitches.map(\.isColorChange) == [false, true, false, false, false])
        #expect(stream.stitches.map(\.isJump) == [false, false, true, false, false])
        #expect(stream.colorChangeCount == 1)
    }

    @Test("Layers assemble in ascending z-order regardless of insertion order")
    func insertionOrderIndependent() {
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 5, y: 5), layer: 2, actor: actor)
        manager.addStitch(at: StagePoint(x: 10, y: 10), layer: 0, actor: actor)

        let stream = manager.assembled()
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 10, y: 10), // layer 0 starts with clause D's point
            EmbroideryPoint(x: 20, y: 20),
            EmbroideryPoint(x: 20, y: 20), // boundary color change
            EmbroideryPoint(x: 20, y: 20), // join jump
            EmbroideryPoint(x: 10, y: 10) // layer 2
        ])
        #expect(stream.stitches.map(\.isColorChange) == [false, false, true, false, false])
        #expect(stream.stitches.map(\.isJump) == [false, false, false, true, false])
        #expect(stream.stitches.map(\.color) == Array(repeating: .black, count: 5))
    }

    @Test("A single-layer manager assembles identically to a direct stream")
    func singleLayerEquivalence() {
        // The equivalence pin for the ops model: Catroid interpolates
        // eagerly per layer and replays; we store stage-space ops and
        // interpolate once at assembly. For one layer and one actor the
        // assembled stream must match feeding the same points straight into
        // an EmbroideryStream — duplicates deduped, long moves interpolated.
        let points = [
            StagePoint(x: 0, y: 0),
            StagePoint(x: 30, y: 40),
            StagePoint(x: 30, y: 40), // deduped in both
            StagePoint(x: 100, y: 0) // 140 units from previous — interpolates
        ]
        var manager = EmbroideryPatternManager()
        var direct = EmbroideryStream()
        for point in points {
            manager.addStitch(at: point, layer: 0, actor: actor)
            direct.addStitch(at: point)
        }

        let assembled = manager.assembled()
        #expect(assembled.stitches == direct.stitches)
        #expect(assembled.colorChangeCount == direct.colorChangeCount)
    }
}
