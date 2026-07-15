import EmbroideryEngine
import Testing

@Suite("EmbroideryPatternManager layer switching and assembly")
struct EmbroideryPatternManagerLayerTests {
    private let actor = ActorID(0)

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
