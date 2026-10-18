import EmbroideryEngine
import Foundation
import Interpreter
import ProgramModel
import Testing

/// Brick backend slice 4: Arc inside the interpreter, and against the Android
/// exports (ADR-047). Geometry and the bridge are in `ArcTests`.
@Suite("Arc in the interpreter")
struct ArcInterpreterTests {
    private static func arc(_ direction: ArcDirection, _ radius: Double, _ degrees: Double) -> Brick {
        .arc(direction: direction, radius: .number(radius), degrees: .number(degrees))
    }

    // MARK: - In the interpreter

    private static func program(_ bricks: [Brick], startHeading: Double = 0) -> Program {
        Program(scenes: [Scene(objects: [Object(startHeading: startHeading, scripts: [Script(bricks: bricks)])])])
    }

    @Test("an arc costs one tick, however many samples it feeds")
    func oneTick() {
        var interpreter = Interpreter(
            program: Self.program([Self.arc(.left, 10, 90), .moveNSteps(.number(5))]),
            clock: InterpreterClock(tickDelta: 0.05)
        )
        guard case let .ticked(first) = interpreter.step(), case let .ticked(second) = interpreter.step() else {
            Issue.record("expected two ticks")
            return
        }
        #expect(first.count {
            if case .needleMoved = $0 {
                true
            } else {
                false
            }
        } == 100)
        #expect(second.count {
            if case .needleMoved = $0 {
                true
            } else {
                false
            }
        } == 1)
        #expect(interpreter.step() == .finished)
    }

    /// ADR-047's order: each update's `.needleMoved`, then that update's own
    /// stitches, then the next update. Emitting all moves first and every stitch
    /// after passes a positions-only comparison (`swift-code-reviewer`, slice 4).
    @Test("each update is followed by its own stitches before the next update")
    func eventsInterleavePerUpdate() {
        var interpreter = Interpreter(
            program: Self.program([.runningStitch(length: .number(1)), Self.arc(.left, 20, 90)]),
            clock: InterpreterClock(tickDelta: 0.05)
        )
        let events = interpreter.run(maxTicks: 100)
        var pattern = RunningStitchPattern(length: 1, start: StagePoint(x: 0, y: 0))
        var expected: [String] = []
        for case let .needleMoved(_, update) in events {
            expected.append("moved \(update.position)")
            expected += pattern.update(update).map { "stitch \($0)" }
        }
        let actual = events.compactMap { event -> String? in
            switch event {
            case let .needleMoved(_, update): "moved \(update.position)"
            case let .stitch(_, position, _, _): "stitch \(position)"
            default: nil
            }
        }
        #expect(expected.count > 100, "the arc must stitch between its updates")
        #expect(actual == expected)
    }

    /// The brief's budget check (ADR-043): the preview budget counts stitches and
    /// a tick's batch is atomic, so what an arc can cost a frame is one tick's
    /// events. A loop of a thousand arcs stays at one arc per tick.
    @Test("a thousand arcs cost at most one arc's events per tick")
    func arcLoopIsBoundedPerTick() {
        var interpreter = Interpreter(
            program: Self.program([.repeatLoop(times: .number(1000)), Self.arc(.left, 10, 360), .loopEnd]),
            clock: InterpreterClock(tickDelta: 0.05)
        )
        var ticks = 0
        var moves = 0
        while case let .ticked(events) = interpreter.step() {
            ticks += 1
            #expect(events.count <= 100, "tick \(ticks) carried \(events.count) events")
            moves += events.count { if case .needleMoved = $0 { true } else { false } }
        }
        #expect(moves == 100_000)
        #expect(ticks == 1000)
    }

    /// The brief's full-circle round trip: a large circle exported and decoded
    /// lands back where it started, with no record moving more than the 121-unit
    /// DST limit (ADR-020's interpolation).
    @Test("a full circle exports in records of at most 121 units and closes")
    func fullCircleRoundTrips() throws {
        var interpreter = Interpreter(
            // The closing `stitch` places a stitch at the needle: a running stitch never
            // stitches the leftover shorter than its length, so only that one can close.
            program: Self.program([.runningStitch(length: .number(60)), Self.arc(.left, 200, 360), .stitch]),
            clock: InterpreterClock(tickDelta: 0.05)
        )
        _ = interpreter.run(maxTicks: 100)
        let records = decodeRecordPositions(try DSTFile(stream: interpreter.assembledStream(), name: "circle").data)
        #expect(records.count > 10)
        var previous = (x: 0, y: 0)
        for record in records {
            #expect(abs(record.x - previous.x) <= 121 && abs(record.y - previous.y) <= 121, "\(record)")
            previous = (record.x, record.y)
        }
        let lastStitch = try #require(records.last { $0.kind == .stitch })
        #expect(abs(lastStitch.x) <= 1 && abs(lastStitch.y) <= 1)
    }

    /// Oracle by composition, not by re-implementation: the stitches the
    /// interpreter emits for a zigzag along an arc equal what `ZigzagStitchPattern`
    /// produces when fed the interpreter's own needle updates in order.
    @Test("a zigzag along an arc stitches each fed update, heading included")
    func zigzagAlongArc() {
        var interpreter = Interpreter(
            program: Self.program([.zigZagStitch(length: .number(2), width: .number(10)), Self.arc(.right, 50, 180)]),
            clock: InterpreterClock(tickDelta: 0.05)
        )
        let events = interpreter.run(maxTicks: 100)
        var pattern = ZigzagStitchPattern(length: 2, width: 10, start: StagePoint(x: 0, y: 0))
        var expected: [StagePoint] = []
        for case let .needleMoved(_, update) in events {
            expected += pattern.update(update)
        }
        let stitched = events.compactMap { event -> StagePoint? in
            if case let .stitch(_, position, _, _) = event {
                position
            } else {
                nil
            }
        }
        #expect(!expected.isEmpty)
        #expect(stitched == expected)
    }

    // MARK: - Android golden exports (D5's only external check)

    /// The kind lives in the third byte's high and low bits only; its middle
    /// bits are ±81 displacement. Masking with `0xF3` kept those, so a jump of
    /// (0, −81) read as a stitch (Codex slice review of slice 4).
    @Test("the decoder tells a jump from a stitch whatever the displacement")
    func decoderSeparatesKindFromDisplacement() {
        let header = Data(count: 512)
        #expect(decodeRecordPositions(header + Data([0x00, 0x00, 0x93]))
            == [DSTRecordPosition(kind: .jump, x: 0, y: -81)])
        #expect(decodeRecordPositions(header + Data([0x00, 0x00, 0x13]))
            == [DSTRecordPosition(kind: .stitch, x: 0, y: -81)])
        #expect(decodeRecordPositions(header + Data([0x00, 0x00, 0xE3]))
            == [DSTRecordPosition(kind: .colorChange, x: 0, y: 81)])
        #expect(decodeRecordPositions(header + Data([0x00, 0x00, 0xF3]))
            == [DSTRecordPosition(kind: .end, x: 0, y: 0)])
    }

    /// Anchored outside the decoder: Android's own header fields must agree with
    /// what the decoder reconstructs (`swift-code-reviewer`, slice 4). Stitch count
    /// and final position agree for every reference file.
    ///
    /// The extents agree for `arc_run` and `go_through` but **not** for
    /// `arc_zigzag`, whose header says `+Y:10` / `−Y:212` while its records span
    /// 0 to −222. Android computes a zigzag's header extents from points other
    /// than the ones it writes, so that file's extents describe the exporter, not
    /// the records, and are not used as an anchor.
    @Test(
        "the decoder agrees with each Android export's own header",
        arguments: ["arc_run", "arc_zigzag", "go_through"]
    )
    func decoderAgreesWithAndroidHeaders(_ name: String) throws {
        let data = try AndroidReference.data(name)
        let header = try DSTHeaderSummary(header: data)
        let decoded = DSTHeaderSummary(records: decodeRecordPositions(data))
        #expect(decoded.stitches == header.stitches)
        #expect(decoded.endX == header.endX && decoded.endY == header.endY)
        if name != "arc_zigzag" {
            #expect(decoded == header)
        }
    }

    @Test("the decoder reads the Android export it is compared against")
    func decoderReadsAndroidExport() throws {
        let records = try decodeRecordPositions(AndroidReference.data("arc_run"))
        #expect(records.count == 41)
        #expect(records.first == DSTRecordPosition(kind: .stitch, x: 0, y: 0))
        #expect(records.last == DSTRecordPosition(kind: .end, x: 56, y: -122))
    }

    @Test("running stitch along two arcs matches the Android export")
    func androidArcRun() throws {
        let ours = try interpretedRecords([
            .runningStitch(length: .number(10)),
            Self.arc(.left, 50, 360),
            Self.arc(.right, 30, 90),
            .moveNSteps(.number(40))
        ])
        try expectMatchesAndroid(ours, decodeRecordPositions(AndroidReference.data("arc_run")))
    }

    @Test("zigzag along an arc matches the Android export")
    func androidArcZigzag() throws {
        let ours = try interpretedRecords([
            .zigZagStitch(length: .number(2), width: .number(10)),
            Self.arc(.right, 50, 180),
            .moveNSteps(.number(50))
        ])
        try expectMatchesAndroid(ours, decodeRecordPositions(AndroidReference.data("arc_zigzag")))
    }
}
