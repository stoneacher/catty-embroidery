import EmbroideryEngine
import Testing

/// The ADR-020 chokepoint seen from the pattern manager, split from
/// `CoordinateChokepointTests` to stay inside `file_length`. The manager is
/// the one component where command time and conversion time are different
/// moments, which is its own class of failure: it stores stage-space ops and
/// converts positions only in the `assembled()` replay, but its clause
/// distance converts a stage *difference* at command time, and it arms
/// stream flags for emissions the replay may still reject.
@Suite("Coordinate chokepoint through the pattern manager (ADR-020)")
struct CoordinateChokepointManagerTests {
    @Test("Adversarial coordinates through the manager leave an assemblable pattern")
    func managerToleratesAdversarialCoordinates() {
        // Two seams, not one: the manager stores stage-space ops and converts
        // positions only in the `assembled()` replay, but its clause distance
        // (`getMaxDistanceBetweenPoints`, clauses B/C/D) converts a stage
        // *difference* at command time — so a second command reaches a
        // conversion before assembly ever runs.
        var manager = EmbroideryPatternManager()
        let actor = ActorID(0)
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: .infinity, y: 0), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: .nan, y: .nan), layer: 1, actor: actor)
        manager.addStitch(at: StagePoint(x: 5e18, y: 5e18), layer: 0, actor: ActorID(1))
        manager.addStitch(at: StagePoint(x: 10, y: 0), layer: 0, actor: actor)

        // The exact surviving trace, not a loose bound (Codex US-210 round 1:
        // asserting only positions and encodability let a cross-actor flag
        // migration through). Layer 0 keeps its two convertible points; every
        // clause-B emission the rejected coordinates generated is skipped
        // whole, and layer 1 — whose single op is NaN — contributes nothing,
        // so it must not leave a colour stop or a join duplicate behind.
        let stream = manager.assembled()
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 0, y: 0),
            EmbroideryPoint(x: 20, y: 0)
        ])
        #expect(stream.stitches.allSatisfy { !$0.isJump && !$0.isColorChange })
        #expect(stream.stitches.map(\.color) == [.black, .black])
        #expect(stream.colorChangeCount == 0)
        expectEveryDeltaEncodable(stream)
    }

    @Test("A rejected emission cannot hand one actor's color change to another")
    func rejectedEmissionDoesNotMigrateAColorChange() {
        // Codex US-210 round 1. The manager arms flags at *command* time and
        // the stream converts at *replay* time, so an emission the stream
        // rejects had already armed `addColorChange()` on the stream — and the
        // stream-global flag then rode the next surviving append, which in an
        // interleaved multi-actor replay belongs to a different actor. Actor
        // A's colour change landing on actor B's stitch contradicts ADR-015
        // ("the actor's next surviving stitch") and ADR-020's own claim that a
        // rejected emission preserves pending state.
        //
        // The replay now asks the stream whether an emission is acceptable
        // before arming anything, so a rejected point costs no change record.
        var manager = EmbroideryPatternManager()
        let actorA = ActorID(0)
        let actorB = ActorID(1)
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actorA)
        manager.setThreadColor(ThreadColor(red: 255, green: 0, blue: 0), for: actorA)
        manager.addStitch(at: StagePoint(x: 5e18, y: 0), layer: 0, actor: actorA) // rejected at replay
        manager.addStitch(at: StagePoint(x: 1, y: 0), layer: 0, actor: actorB)
        manager.addStitch(at: StagePoint(x: 2, y: 0), layer: 0, actor: actorA)

        let stream = manager.assembled()
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 0, y: 0),
            EmbroideryPoint(x: 2, y: 0), // clause E — actor B, and it must be flag-free
            EmbroideryPoint(x: 2, y: 0), // clause B for A's return: the change belongs here
            EmbroideryPoint(x: 2, y: 0),
            EmbroideryPoint(x: 4, y: 0)
        ])
        #expect(stream.stitches.map(\.isColorChange) == [false, false, true, false, false])
        #expect(stream.stitches.allSatisfy { !$0.isJump })
        // Only the realized change counts, so `CO = changes + 1` still holds.
        #expect(stream.colorChangeCount == 1)
    }

    @Test("An actor whose armed color change is rejected loses it — the pinned exception")
    func rejectedStitchLosesItsOwnActorsColorChange() {
        // ADR-020 accepts this rather than fixing it, so it is pinned rather
        // than left to inference (Codex US-210 round 2: the cross-actor test
        // could conceal it, because there a later clause-B change appears).
        // The manager clears the actor's pending bit at *command* time and
        // cannot know the replay will drop the point, so A's red arrives with
        // no change record at all. Under-counting is the right direction: the
        // alternative is a record attached to a stitch that does not exist.
        var manager = EmbroideryPatternManager()
        let actor = ActorID(0)
        let red = ThreadColor(red: 255, green: 0, blue: 0)
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actor)
        manager.setThreadColor(red, for: actor)
        manager.addStitch(at: StagePoint(x: 5e18, y: 0), layer: 0, actor: actor) // rejected at replay
        manager.addStitch(at: StagePoint(x: 10, y: 0), layer: 0, actor: actor)

        let stream = manager.assembled()
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 0, y: 0),
            EmbroideryPoint(x: 20, y: 0)
        ])
        #expect(stream.stitches.map(\.color) == [.black, red])
        #expect(stream.stitches.allSatisfy { !$0.isColorChange })
        #expect(stream.colorChangeCount == 0)
    }

    @Test("A manager holding only rejected points reports a pattern but assembles nothing")
    func rejectedOnlyPatternAssemblesEmpty() {
        // Characterization, not an endorsement (Codex US-210 round 2):
        // `hasValidPattern` counts *recorded* ops, which the replay may reject,
        // so the two can disagree. Nothing in the engine currently promises
        // they agree; a caller gating export on it would show an empty design
        // as exportable. Recorded in ADR-020 for whoever wires up export.
        var manager = EmbroideryPatternManager()
        let actor = ActorID(0)
        manager.addStitch(at: StagePoint(x: .infinity, y: 0), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: .nan, y: 0), layer: 0, actor: actor)

        #expect(manager.hasValidPattern)
        #expect(manager.assembled().stitches.isEmpty)
    }

}
