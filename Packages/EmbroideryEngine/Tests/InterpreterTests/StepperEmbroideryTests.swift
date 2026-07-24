import EmbroideryEngine
import Foundation
import Interpreter
import ProgramModel
import Testing

/// US-206: the eight embroidery bricks driving the engine's `RunningStitch`,
/// `SewUp`, and `EmbroideryPatternManager`, yielding an `EmbroideryStream`. The
/// interpreter only *calls* the engine — dedup / interpolation / color-change /
/// layer logic stay owned by the engine (ADR-012/013/015). Expected geometry is
/// cross-checked against the US-107–US-110 engine oracles, never invented.
@Suite("Stepper embroidery")
struct StepperEmbroideryTests {
    private let clock = InterpreterClock(tickDelta: 0.05)

    // MARK: - Helpers

    /// The stitch positions, in emission order, from an event stream.
    private func stitchPositions(_ events: [InterpreterEvent]) -> [StagePoint] {
        events.compactMap {
            if case let .stitch(_, position, _) = $0 {
                position
            } else {
                nil
            }
        }
    }

    /// The `colorArmed` hex intents, in order.
    private func colorArmedHexes(_ events: [InterpreterEvent]) -> [String] {
        events.compactMap {
            if case let .colorArmed(_, hex) = $0 {
                hex
            } else {
                nil
            }
        }
    }

    /// Approximate stage-point comparison per ADR-014 — the zigzag/sew-up
    /// offsets go through `sin`/`cos`, whose Double results carry transcendental
    /// dust, so exact `==` cannot hold (mirrors the engine test helper).
    private func expect(
        _ actual: [StagePoint],
        approximates expected: [StagePoint],
        tolerance: Double = 1e-9,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard actual.count == expected.count else {
            Issue.record(
                "expected \(expected.count) points \(expected), got \(actual)",
                sourceLocation: sourceLocation
            )
            return
        }
        for (index, pair) in zip(actual, expected).enumerated() {
            #expect(
                abs(pair.0.x - pair.1.x) <= tolerance && abs(pair.0.y - pair.1.y) <= tolerance,
                "point \(index): \(pair.0) !≈ \(pair.1)",
                sourceLocation: sourceLocation
            )
        }
    }

    private func interpreter(_ bricks: [Brick], object: Object? = nil) -> Interpreter {
        let object = object ?? Object(scripts: [Script(bricks: bricks)])
        return Interpreter(program: Program(scenes: [Scene(objects: [object])]), clock: clock)
    }

    // MARK: - Item 1 — running stitch driven by motion

    @Test("runningStitch(2) then a move of 10 stitches at 0,2,…,10, as events and in the stream")
    func runningStitchDrivenByMotion() {
        // Object at (0,0) heading 0 (up): moving 10 advances +y by 10. The
        // engine emits the lazy anchor plus interpolants (US-107 straightLine).
        var interpreter = interpreter([
            .runningStitch(length: .number(2)),
            .moveNSteps(.number(10))
        ])
        let events = interpreter.run(maxTicks: 100)

        #expect(stitchPositions(events) == [
            StagePoint(x: 0, y: 0), StagePoint(x: 0, y: 2), StagePoint(x: 0, y: 4),
            StagePoint(x: 0, y: 6), StagePoint(x: 0, y: 8), StagePoint(x: 0, y: 10)
        ])
        // Assembled: factor-2 conversion, no dedup (all distinct), no
        // interpolation (each 2-stage gap is 4 units, well under ±121).
        let stream = interpreter.assembledStream()
        #expect(stream.stitches.map(\.position) == [
            EmbroideryPoint(x: 0, y: 0), EmbroideryPoint(x: 0, y: 4), EmbroideryPoint(x: 0, y: 8),
            EmbroideryPoint(x: 0, y: 12), EmbroideryPoint(x: 0, y: 16), EmbroideryPoint(x: 0, y: 20)
        ])
        #expect(stream.colorChangeCount == 0)
    }

    // MARK: - Item 2 — the stitch brick emits one point and re-anchors

    @Test("the stitch brick emits exactly one point at the needle and re-anchors the running stitch")
    func stitchBrickReAnchors() {
        // runningStitch(5); move +3 (sub-length, emits nothing, anchor stays
        // (0,0)); stitch (one point at (0,3), re-anchor to (0,3)); move +5.
        // The final run measures from (0,3): distance 5 crosses once →
        // [(0,3),(0,8)]. With a stale (0,0) anchor the move to (0,8) would
        // instead give [(0,0),(0,5)] — the discriminating outcome.
        var interpreter = interpreter([
            .runningStitch(length: .number(5)),
            .moveNSteps(.number(3)),
            .stitch,
            .moveNSteps(.number(5))
        ])

        _ = interpreter.step() // runningStitch — activate, no stitch
        _ = interpreter.step() // move +3 — sub-length, no stitch
        // The stitch-brick tick emits exactly one stitch, at the needle.
        guard case let .ticked(stitchTick) = interpreter.step() else {
            Issue.record("expected a ticked outcome for the stitch brick")
            return
        }
        #expect(stitchPositions(stitchTick) == [StagePoint(x: 0, y: 3)])

        let rest = interpreter.run(maxTicks: 100) // move +5
        #expect(stitchPositions(rest) == [StagePoint(x: 0, y: 3), StagePoint(x: 0, y: 8)])
    }

    // MARK: - Item 3 — set thread color: silent start, arm after emission (ADR-015)

    @Test("setThreadColor before any emission adds no color change — the silent start")
    func setThreadColorSilentStart() {
        var interpreter = interpreter([
            .setThreadColor(hex: "#00ff00"),
            .runningStitch(length: .number(2)),
            .moveNSteps(.number(4))
        ])
        let events = interpreter.run(maxTicks: 100)

        // Intent still surfaces as a colorArmed event…
        #expect(colorArmedHexes(events) == ["#00ff00"])
        // …but the manager silently selects the starting color: no change record.
        #expect(interpreter.assembledStream().colorChangeCount == 0)
    }

    @Test("a differing setThreadColor after emission arms exactly one change on the next stitch")
    func setThreadColorArmsAfterEmission() {
        // Default thread color is black; stitch three points, then set green
        // (differs) and stitch more — one change lands on the next survivor.
        var interpreter = interpreter([
            .runningStitch(length: .number(2)),
            .moveNSteps(.number(4)),
            .setThreadColor(hex: "#00ff00"),
            .moveNSteps(.number(4))
        ])
        let events = interpreter.run(maxTicks: 100)

        #expect(colorArmedHexes(events) == ["#00ff00"])
        #expect(interpreter.assembledStream().colorChangeCount == 1)
    }

    @Test("setThreadColor with invalid hex is a full manager no-op yet still arms the intent event")
    func setThreadColorInvalidHex() {
        // The manager no-ops on malformed input (ADR-015), but colorArmed is
        // the brick's intent and fires regardless of that decision.
        var interpreter = interpreter([
            .runningStitch(length: .number(2)),
            .moveNSteps(.number(4)),
            .setThreadColor(hex: "not-a-color"),
            .moveNSteps(.number(4))
        ])
        let events = interpreter.run(maxTicks: 100)

        #expect(colorArmedHexes(events) == ["not-a-color"])
        #expect(interpreter.assembledStream().colorChangeCount == 0)
    }

    // MARK: - Formula-type contract (US-202): interpretInteger vs interpretFloat

    @Test("runningStitch length comes through interpretInteger — 2.9 truncates toward zero to 2")
    func runningStitchUsesInterpretInteger() {
        // A whole-number literal cannot tell the contracts apart; a fractional
        // one does. interpretInteger truncates 2.9 → 2, so the run stitches at
        // length-2 spacing. An interpretFloat/Double regression would keep 2.9
        // and diverge. Cross-checked against the engine pattern at length 2.
        var interpreter = interpreter([
            .runningStitch(length: .number(2.9)),
            .moveNSteps(.number(10))
        ])
        let events = interpreter.run(maxTicks: 100)

        var reference = RunningStitchPattern(length: 2, start: StagePoint(x: 0, y: 0))
        let expected = reference.update(NeedleUpdate(position: StagePoint(x: 0, y: 10)))
        #expect(stitchPositions(events) == expected)
    }

    @Test("zigZagStitch length and width come through interpretFloat — a fractional length is preserved")
    func zigZagUsesInterpretFloat() {
        // interpretFloat keeps 2.5; an interpretInteger regression would
        // truncate to 2 and diverge. Oracle: the engine pattern fed the same
        // fractional length/width and the same needle update.
        var interpreter = interpreter([
            .zigZagStitch(length: .number(2.5), width: .number(4)),
            .moveNSteps(.number(5))
        ])
        let events = interpreter.run(maxTicks: 100)

        var reference = ZigzagStitchPattern(length: 2.5, width: 4, start: StagePoint(x: 0, y: 0))
        let expected = reference.update(NeedleUpdate(position: StagePoint(x: 0, y: 5), heading: 0))
        expect(stitchPositions(events), approximates: expected)
    }

    // MARK: - Item 4 — zigzag and triple activation reproduce the pattern geometry

    @Test("zigZagStitch activation reproduces the US-108 vertical-line geometry")
    func zigZagStitchActivation() {
        // Port of ZigzagStitchPattern verticalLine: length 10, width 5, up 20.
        var interpreter = interpreter([
            .zigZagStitch(length: .number(10), width: .number(5)),
            .moveNSteps(.number(20))
        ])
        let events = interpreter.run(maxTicks: 100)
        expect(stitchPositions(events), approximates: [
            StagePoint(x: -2.5, y: 0), StagePoint(x: 2.5, y: 10), StagePoint(x: -2.5, y: 20)
        ])
    }

    @Test("tripleStitch activation reproduces the US-109 forward-back-forward geometry")
    func tripleStitchActivation() {
        // Triple is trig-free (exact ==): length 10, up 20 → anchor + two
        // segments, each new/previous/new (US-109 simpleMove chained).
        var interpreter = interpreter([
            .tripleStitch(length: .number(10)),
            .moveNSteps(.number(20))
        ])
        let events = interpreter.run(maxTicks: 100)
        #expect(stitchPositions(events) == [
            StagePoint(x: 0, y: 0),
            StagePoint(x: 0, y: 10), StagePoint(x: 0, y: 0), StagePoint(x: 0, y: 10),
            StagePoint(x: 0, y: 20), StagePoint(x: 0, y: 10), StagePoint(x: 0, y: 20)
        ])
    }

    // MARK: - Item 5 — sew-up bar tack; stop halts stitching

    @Test("sewUp emits the 5-point bar tack around the needle")
    func sewUpBarTack() {
        // Port of SewUp verticalSewUp: heading 0 → center/ahead/center/behind/center.
        var interpreter = interpreter([.sewUp])
        let events = interpreter.run(maxTicks: 100)
        expect(stitchPositions(events), approximates: [
            StagePoint(x: 0, y: 0), StagePoint(x: 0, y: 3), StagePoint(x: 0, y: 0),
            StagePoint(x: 0, y: -3), StagePoint(x: 0, y: 0)
        ])
    }

    @Test("stopRunningStitch halts stitching — subsequent motion emits no stitches")
    func stopRunningStitchHaltsStitching() {
        var interpreter = interpreter([
            .runningStitch(length: .number(2)),
            .stopRunningStitch,
            .moveNSteps(.number(10))
        ])
        let events = interpreter.run(maxTicks: 100)

        // The move still moves the needle, but the stopped wrapper stitches nothing.
        #expect(stitchPositions(events).isEmpty)
        #expect(events.contains {
            if case .needleMoved = $0 {
                true
            } else {
                false
            }
        })
    }

    // MARK: - Item 6 — writeEmbroideryToFile is a finalize marker, no I/O

    @Test("writeEmbroideryToFile produces a finalizeRequested event and touches no file system")
    func writeEmbroideryToFileFinalizes() {
        var interpreter = interpreter([.writeEmbroideryToFile(name: "design")])
        // The brick performs no I/O — it only emits the marker event.
        #expect(interpreter.run(maxTicks: 100) == [.finalizeRequested(name: "design")])
    }

    // MARK: - Item 7 — two objects assemble in layer order (US-110 oracle)

    @Test("two objects with different zIndex assemble in ascending layer order")
    func twoObjectsAssembleInLayerOrder() {
        // Object A created first, zIndex 2, stitches at (5,5); object B created
        // second, zIndex 0, stitches at (10,10). One tick, creation order: A
        // then B. Cross-checked against a raw manager fed the same calls.
        let objectA = Object(name: "a", startX: 5, startY: 5, zIndex: 2, scripts: [Script(bricks: [.stitch])])
        let objectB = Object(name: "b", startX: 10, startY: 10, zIndex: 0, scripts: [Script(bricks: [.stitch])])
        var interpreter = Interpreter(
            program: Program(scenes: [Scene(objects: [objectA, objectB])]), clock: clock
        )
        _ = interpreter.run(maxTicks: 100)

        var reference = EmbroideryPatternManager()
        reference.addStitch(at: StagePoint(x: 5, y: 5), layer: 2, actor: ActorID(0))
        reference.addStitch(at: StagePoint(x: 10, y: 10), layer: 0, actor: ActorID(1))

        let assembled = interpreter.assembledStream()
        #expect(assembled == reference.assembled())
        // Layer order, not creation order: object B (zIndex 0) leads even
        // though object A was created first.
        #expect(assembled.firstStitchPosition == EmbroideryPoint(x: 20, y: 20))
    }
}
