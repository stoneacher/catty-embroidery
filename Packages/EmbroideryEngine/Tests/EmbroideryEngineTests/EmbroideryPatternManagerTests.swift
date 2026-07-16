import EmbroideryEngine
import Testing

@Suite("EmbroideryPatternManager")
struct EmbroideryPatternManagerTests {
    private let red = ThreadColor(red: 255, green: 0, blue: 0)
    private let blue = ThreadColor(red: 0, green: 0, blue: 255)
    private let actor = ActorID(0)
    private let otherActor = ActorID(1)

    // MARK: - Thread color emission (US-110; ADR-012 deliberate divergence)

    // Android's Set Thread Color brick only sets `Sprite.embroideryThreadColor`
    // and never emits machine-level changes; ADR-012 pins our divergence: a
    // newly set color that differs from the current one arms a DST color
    // change. ADR-015 pins the edges decided in planning: silent before the
    // first emitted stitch, and invalid hex is a full no-op.

    @Test("Setting a differing color flags the next stitch and counts in CO")
    func differingColorFlagsNextStitch() {
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actor)
        manager.setThreadColor(hexString: "#FF0000", for: actor)
        manager.addStitch(at: StagePoint(x: 5, y: 5), layer: 0, actor: actor)

        let stream = manager.assembled()
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 0, y: 0),
            EmbroideryPoint(x: 10, y: 10)
        ])
        #expect(stream.stitches.map(\.isColorChange) == [false, true])
        #expect(stream.stitches.map(\.color) == [.black, red])
        #expect(stream.colorChangeCount == 1)

        // CO counts color *blocks* = changes + 1 (US-104, ADR-012). The CO
        // field sits at fixed offsets 31..<36 (pinned by DSTHeaderTests).
        let header = DSTHeader(stream: stream, name: "us110")
        #expect(Array(header.bytes[31 ..< 36]) == Array("CO:".utf8) + [UInt8(ascii: "2"), 0x00])
    }

    @Test("Setting the current color is a no-op")
    func sameColorNoOp() {
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actor)
        manager.setThreadColor(hexString: "#000000", for: actor) // default black
        manager.addStitch(at: StagePoint(x: 5, y: 5), layer: 0, actor: actor)
        manager.setThreadColor(hexString: "#FF0000", for: actor) // differs — arms
        manager.addStitch(at: StagePoint(x: 10, y: 10), layer: 0, actor: actor)
        manager.setThreadColor(hexString: "#ff0000", for: actor) // same again
        manager.addStitch(at: StagePoint(x: 15, y: 15), layer: 0, actor: actor)

        let stream = manager.assembled()
        #expect(stream.stitches.map(\.isColorChange) == [false, false, true, false])
        #expect(stream.stitches.map(\.color) == [.black, .black, red, red])
        #expect(stream.colorChangeCount == 1)
    }

    @Test("Invalid hex leaves the color unchanged and emits nothing")
    func invalidHexUnchanged() {
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actor)
        manager.setThreadColor(hexString: "#gg0000", for: actor)
        manager.addStitch(at: StagePoint(x: 5, y: 5), layer: 0, actor: actor)

        let stream = manager.assembled()
        #expect(stream.stitches.map(\.isColorChange) == [false, false])
        #expect(stream.stitches.map(\.color) == [.black, .black])
        #expect(stream.colorChangeCount == 0)
    }

    @Test("Setting a color before the first stitch is silent (ADR-015)")
    func setBeforeFirstStitchSilent() {
        // Choosing block 1's color must not create an empty leading color
        // block — Catroid only ever inserts color changes into non-empty
        // streams. A differing set after stitching still arms.
        var manager = EmbroideryPatternManager()
        manager.setThreadColor(hexString: "#FF0000", for: actor)
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: 5, y: 5), layer: 0, actor: actor)
        manager.setThreadColor(hexString: "#0000FF", for: actor)
        manager.addStitch(at: StagePoint(x: 10, y: 10), layer: 0, actor: actor)

        let stream = manager.assembled()
        #expect(stream.stitches.map(\.isColorChange) == [false, false, true])
        #expect(stream.stitches.map(\.color) == [red, red, blue])
        #expect(stream.colorChangeCount == 1)
    }

    @Test("A pending color change survives a deduped command")
    func pendingChangeSurvivesDedup() {
        // Clause A returns before the pending change is consumed, mirroring
        // the stream-level rule from US-109: the armed flag lands on the
        // next surviving stitch.
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 5, y: 5), layer: 0, actor: actor)
        manager.setThreadColor(red, for: actor)
        manager.addStitch(at: StagePoint(x: 5, y: 5), layer: 0, actor: actor) // deduped
        manager.addStitch(at: StagePoint(x: 6, y: 6), layer: 0, actor: actor)

        let stream = manager.assembled()
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 10, y: 10),
            EmbroideryPoint(x: 12, y: 12)
        ])
        #expect(stream.stitches.map(\.isColorChange) == [false, true])
        #expect(stream.stitches.map(\.color) == [.black, red])
        #expect(stream.colorChangeCount == 1)
    }

    @Test("An invalid hex set after arming keeps the pending change and the color")
    func invalidHexAfterArmingKeepsPending() {
        // The full no-op (ADR-015) must hold from any state: garbage after a
        // differing set neither clears the armed change nor the new color.
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actor)
        manager.setThreadColor(red, for: actor)
        manager.setThreadColor(hexString: "#gg0000", for: actor)
        manager.addStitch(at: StagePoint(x: 5, y: 5), layer: 0, actor: actor)

        let stream = manager.assembled()
        #expect(stream.stitches.map(\.isColorChange) == [false, true])
        #expect(stream.stitches.map(\.color) == [.black, red])
        #expect(stream.colorChangeCount == 1)
    }

    @Test("An actor-change transition and a pending change meet in one command")
    func actorChangeMeetsPendingChange() {
        // The only place two color-change sources compose: actor B sets a
        // color after actor A emitted (arming counts manager-wide, ADR-015 —
        // B itself never stitched), then stitches onto A's layer. Clause B
        // contributes the black transition pair with one change; clause E's
        // target carries B's pending change — two changes total.
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actor)
        manager.setThreadColor(red, for: otherActor)
        manager.addStitch(at: StagePoint(x: 5, y: 5), layer: 0, actor: otherActor)

        let stream = manager.assembled()
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 0, y: 0),
            EmbroideryPoint(x: 0, y: 0), // clause B, color change
            EmbroideryPoint(x: 0, y: 0), // clause B, emitted again
            EmbroideryPoint(x: 10, y: 10) // clause E, pending change
        ])
        #expect(stream.stitches.map(\.isColorChange) == [false, true, false, true])
        #expect(stream.stitches.map(\.color) == [.black, .black, .black, red])
        #expect(stream.colorChangeCount == 2)
    }

    @Test("In-layer changes and a layer boundary sum into one CO count")
    func changesAndBoundarySumInCO() {
        // Layer 0: black → red → blue (two armed changes), then a stitch on
        // layer 1. Clause D connects the layers (distance < 121) and the
        // assembler inserts the boundary change + join jump, so the machine
        // sees three color stops → CO 4.
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actor)
        manager.setThreadColor(red, for: actor)
        manager.addStitch(at: StagePoint(x: 5, y: 5), layer: 0, actor: actor)
        manager.setThreadColor(blue, for: actor)
        manager.addStitch(at: StagePoint(x: 10, y: 10), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: 20, y: 20), layer: 1, actor: actor)

        let stream = manager.assembled()
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 0, y: 0),
            EmbroideryPoint(x: 10, y: 10),
            EmbroideryPoint(x: 20, y: 20),
            EmbroideryPoint(x: 20, y: 20), // boundary re-emit of layer 0's last point
            EmbroideryPoint(x: 20, y: 20), // join duplicate ahead of layer 1
            EmbroideryPoint(x: 20, y: 20), // clause D: previous command's point
            EmbroideryPoint(x: 40, y: 40)
        ])
        #expect(stream.stitches.map(\.isColorChange) == [false, true, true, true, false, false, false])
        #expect(stream.stitches.map(\.isJump) == [false, false, false, false, true, false, false])
        #expect(stream.stitches.map(\.color) == [.black, red, blue, blue, blue, blue, blue])
        #expect(stream.colorChangeCount == 3)

        let header = DSTHeader(stream: stream, name: "us110")
        #expect(Array(header.bytes[31 ..< 36]) == Array("CO:".utf8) + [UInt8(ascii: "4"), 0x00])
    }

    // MARK: - Workspace dedup with the actor dimension (US-110; ADR-012)

    // Catroid `DSTStitchCommand.act` clause A: a command whose coordinates
    // equal the layer workspace's current position *from the same actor*
    // emits nothing. US-109 landed the positional slice on the stream; the
    // actor clause lives here.

    @Test("An identical consecutive command from the same actor emits nothing")
    func sameActorSamePositionDropped() {
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 5, y: 5), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: 5, y: 5), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: 6, y: 6), layer: 0, actor: actor)

        #expect(manager.assembled().stitches.map(\.position) == [
            EmbroideryPoint(x: 10, y: 10),
            EmbroideryPoint(x: 12, y: 12)
        ])
    }

    @Test("The same position from a different actor is not deduped — clause B fires")
    func differentActorSamePositionNotDeduped() {
        // Actor change: color change armed, the workspace position emitted
        // twice (Catroid emits these with the never-set workspace color —
        // black, ADR-015 provenance note), then the target.
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 5, y: 5), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: 5, y: 5), layer: 0, actor: otherActor)

        let stream = manager.assembled()
        #expect(stream.stitches.map(\.position) == Array(
            repeating: EmbroideryPoint(x: 10, y: 10), count: 4
        ))
        #expect(stream.stitches.map(\.isColorChange) == [false, true, false, false])
        #expect(stream.stitches.map(\.isJump) == [false, false, false, false])
        #expect(stream.colorChangeCount == 1)
    }

    @Test("The actor-change double emission bypasses stream dedup")
    func actorChangeDoubleEmitBypassesDedup() {
        // The ⚠️ case from the story: clause B emits the workspace position
        // twice consecutively at stream level — below the workspace dedup.
        // Those emissions must survive into the assembled stream.
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: 5, y: 5), layer: 0, actor: otherActor)

        let stream = manager.assembled()
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 0, y: 0),
            EmbroideryPoint(x: 0, y: 0), // clause B, workspace position
            EmbroideryPoint(x: 0, y: 0), // clause B, emitted again
            EmbroideryPoint(x: 10, y: 10)
        ])
        #expect(stream.stitches.map(\.isColorChange) == [false, true, false, false])
        #expect(stream.colorChangeCount == 1)
    }

    @Test("Clause B arms a jump between the double emission when the target is far")
    func actorChangeFarTargetArmsJump() {
        // Chebyshev distance (0,0)→(100,0) = 200 units > 121, so clause B
        // inserts addJump() between its two workspace-position emissions;
        // the far target then interpolates on replay (US-105 semantics).
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 0, y: 0), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: 100, y: 0), layer: 0, actor: otherActor)

        let stream = manager.assembled()
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 0, y: 0),
            EmbroideryPoint(x: 0, y: 0), // clause B, color change
            EmbroideryPoint(x: 0, y: 0), // clause B, jump armed
            EmbroideryPoint(x: 0, y: 0), // interpolation: duplicate-of-previous
            EmbroideryPoint(x: 100, y: 0), // interpolation: intermediate
            EmbroideryPoint(x: 200, y: 0), // interpolation: target as jump
            EmbroideryPoint(x: 200, y: 0) // plain target
        ])
        #expect(stream.stitches.map(\.isColorChange) == [false, true, false, false, false, false, false])
        #expect(stream.stitches.map(\.isJump) == [false, false, true, true, true, true, false])
        #expect(stream.colorChangeCount == 1)
    }

    @Test("A deduped command still updates the actor's last command")
    func dedupedCommandUpdatesLastCommand() {
        // Catroid's `addStitchCommand` records the command in the per-sprite
        // map even when `act` dedup-returns. Observable: after the dedup on
        // layer 0, the next layer-1 command sees a *layer-0* previous
        // command, so clauses C and D fire. Had the dedup not updated it,
        // the previous command would still be the layer-1 one and only
        // clause E would run (6 stitches, 1 change instead of 9 and 2).
        var manager = EmbroideryPatternManager()
        manager.addStitch(at: StagePoint(x: 5, y: 5), layer: 0, actor: actor)
        manager.addStitch(at: StagePoint(x: 5, y: 5), layer: 1, actor: actor)
        manager.addStitch(at: StagePoint(x: 5, y: 5), layer: 0, actor: actor) // deduped
        manager.addStitch(at: StagePoint(x: 6, y: 6), layer: 1, actor: actor)

        let stream = manager.assembled()
        let at10 = EmbroideryPoint(x: 10, y: 10)
        #expect(stream.stitches.map(\.position) == [
            at10, // layer 0
            at10, // boundary color change
            at10, // join jump
            at10, at10, // layer 1: clause D + E of the second command
            at10, at10, at10, // fourth command: clause C (change, prev, jump, prev)…
            EmbroideryPoint(x: 12, y: 12) // …clause D, then E target
        ])
        #expect(stream.stitches.map(\.isColorChange) == [
            false, true, false, false, false, true, false, false, false
        ])
        #expect(stream.stitches.map(\.isJump) == [
            false, false, true, false, false, false, true, false, false
        ])
        #expect(stream.colorChangeCount == 2)
    }
}
