import EmbroideryEngine
import Foundation
import Interpreter
import ProgramModel
import Testing

/// Brick backend slice 4: Catroid's Arc (`content/actions/ArcAction.kt`), with
/// the brief's D5–D7 adaptations (ADR-047): samples i = 1…100, a degenerate
/// guard, compute-then-commit, catch-and-skip, and the chord heading mirrored.
@Suite("Arc")
struct ArcTests {
    private let scope = VariableScope()
    private let throwing = Formula.binary(.divide, .number(0), .number(0))

    private static func arc(_ direction: ArcDirection, _ radius: Double, _ degrees: Double) -> Brick {
        .arc(direction: direction, radius: .number(radius), degrees: .number(degrees))
    }

    private func close(_ lhs: Double, _ rhs: Double, _ tolerance: Double = 1e-9) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    private func updates(
        _ brick: Brick, from position: StagePoint = StagePoint(x: 0, y: 0), heading: Double = 0
    ) throws -> (updates: [NeedleUpdate], needle: VirtualNeedle) {
        var needle = VirtualNeedle(position: position, heading: heading)
        let emitted = needle.apply(brick, scope: scope)
        let updates = try #require(emitted)
        return (updates, needle)
    }

    // MARK: - Geometry

    /// From (0, 0) facing up, a left arc's centre is 10 to the left, so a
    /// quarter ends at (−10, 10). The heading is the last chord's direction
    /// (D6, mirrored from Catroid): −89.55°, not the tangent's −90°.
    @Test("a quarter left arc ends at (−10, 10), facing along its last chord")
    func quarterLeft() throws {
        let (updates, needle) = try updates(Self.arc(.left, 10, 90))
        #expect(updates.count == 100)
        #expect(close(needle.position.x, -10) && close(needle.position.y, 10))
        #expect(close(needle.heading, -89.55))
        #expect(updates.last == NeedleUpdate(position: needle.position, heading: needle.heading))
    }

    @Test("a quarter right arc ends at (10, 10), facing along its last chord")
    func quarterRight() throws {
        let (_, needle) = try updates(Self.arc(.right, 10, 90))
        #expect(close(needle.position.x, 10) && close(needle.position.y, 10))
        #expect(close(needle.heading, 89.55))
    }

    /// Named so the chord heading is never "fixed" to the tangent by accident.
    @Test("final heading is the last chord, not the tangent")
    func finalHeadingIsTheLastChordNotTheTangent() throws {
        let (_, needle) = try updates(Self.arc(.left, 10, 90))
        #expect(!close(needle.heading, -90, 1e-3))
    }

    /// Each fed sample turns the needle to the chord it just travelled, as
    /// `ArcAction.update` does (`atan2(dx, dy)` is the compass bearing).
    @Test("every update faces along the chord leading to it")
    func everyUpdateFacesItsChord() throws {
        let start = StagePoint(x: 3, y: 4)
        let (updates, _) = try updates(Self.arc(.right, 25, 200), from: start, heading: 30)
        var previous = start
        for update in updates {
            let bearing = atan2(update.position.x - previous.x, update.position.y - previous.y) * 180 / .pi
            #expect(close(update.heading, bearing), "\(update)")
            previous = update.position
        }
    }

    @Test("every sample lies on the arc's circle")
    func everySampleOnTheCircle() throws {
        let start = StagePoint(x: 3, y: 4)
        let heading = 30.0
        let radians = heading * .pi / 180
        // A left arc's centre lies on the heading's left normal (−cos h, sin h).
        let centre = StagePoint(x: start.x - 10 * cos(radians), y: start.y + 10 * sin(radians))
        let (updates, _) = try updates(Self.arc(.left, 10, 270), from: start, heading: heading)
        // Exactly 100 from an off-origin start, where Catroid's i = 0 sample would
        // reconstruct the start with a residual and be fed as a 101st.
        #expect(updates.count == 100)
        for update in updates {
            let distance = hypot(update.position.x - centre.x, update.position.y - centre.y)
            #expect(close(distance, 10), "\(update)")
        }
    }

    @Test("negative degrees turn the other way, negative radius is the same arc")
    func signEquivalences() throws {
        let start = StagePoint(x: -7, y: 2)
        #expect(try updates(Self.arc(.left, 12, -135), from: start, heading: 20).updates
            == updates(Self.arc(.right, 12, 135), from: start, heading: 20).updates)
        #expect(try updates(Self.arc(.right, 12, -135), from: start, heading: 20).updates
            == updates(Self.arc(.left, 12, 135), from: start, heading: 20).updates)
        #expect(try updates(Self.arc(.left, -12, 135), from: start, heading: 20).updates
            == updates(Self.arc(.left, 12, 135), from: start, heading: 20).updates)
    }

    // MARK: - Degenerate, non-finite and bad input: one unchanged update

    /// The last case is Codex's brief-review cancellation input: at 0° every
    /// sample reconstructs the start through `centre + r·(cos, sin)` with a
    /// binary64 residual, so skipping i = 0 alone would still feed and turn.
    @Test("a degenerate arc emits one unchanged update", arguments: [
        (10.0, 0.0, StagePoint(x: 0, y: 0), 0.0),
        (0, 90, StagePoint(x: 0, y: 0), 0),
        (0, 90, StagePoint(x: 5, y: -5), 45),
        (10, 0, StagePoint(x: 0.1, y: 0.2), 33)
    ])
    func degenerate(_ radius: Double, _ degrees: Double, _ start: StagePoint, _ heading: Double) throws {
        let (updates, needle) = try updates(Self.arc(.left, radius, degrees), from: start, heading: heading)
        #expect(updates == [NeedleUpdate(position: start, heading: heading)])
        #expect(needle == VirtualNeedle(position: start, heading: heading))
    }

    /// `r = MAX` makes `centre + r·cos` overflow to ±∞ partway round; nothing
    /// is committed, so the needle never holds a non-finite coordinate.
    @Test("an arc whose samples overflow leaves the needle unchanged")
    func overflowSkips() throws {
        let (updates, needle) = try updates(Self.arc(.left, .greatestFiniteMagnitude, 180), heading: 0)
        #expect(updates == [NeedleUpdate(position: StagePoint(x: 0, y: 0), heading: 0)])
        #expect(needle == VirtualNeedle())
    }

    /// Catch-and-skip like `moveNSteps` (ADR-018), not Catroid's accident of
    /// stitching from the stage origin with unassigned action fields.
    @Test("a bad formula skips the arc")
    func badFormulaSkips() throws {
        let start = StagePoint(x: 4, y: 4)
        for brick in [
            Brick.arc(direction: .left, radius: throwing, degrees: .number(90)),
            .arc(direction: .left, radius: .number(10), degrees: throwing)
        ] {
            let (updates, needle) = try updates(brick, from: start, heading: 10)
            #expect(updates == [NeedleUpdate(position: start, heading: 10)])
            #expect(needle == VirtualNeedle(position: start, heading: 10))
        }
    }

    /// D5's pinned divergence (Codex brief review, finding 1): Catroid stores
    /// the look's position as `float`, so at 2³⁰ a radius-20 arc never changes
    /// it and nothing is stitched. The needle is `Double` (ADR-014), so here it
    /// moves and feeds every sample.
    @Test("at large coordinates the Double needle still moves (pinned divergence)")
    func largeCoordinateFeedDivergence() throws {
        let start = StagePoint(x: 1_073_741_824, y: 1_073_741_824)
        let (updates, needle) = try updates(Self.arc(.left, 20, 90), from: start)
        #expect(updates.count == 100)
        #expect(close(needle.position.x, start.x - 20, 1e-6) && close(needle.position.y, start.y + 20, 1e-6))
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

    private static func ourRecords(_ bricks: [Brick]) throws -> [DSTRecordPosition] {
        var interpreter = Interpreter(
            program: program(bricks, startHeading: 90),
            clock: InterpreterClock(tickDelta: 0.05)
        )
        _ = interpreter.run(maxTicks: 1000)
        return try decodeRecordPositions(DSTFile(stream: interpreter.assembledStream(), name: "arc").data)
    }

    private static func expectWithinOneUnit(
        _ ours: [DSTRecordPosition], _ android: [DSTRecordPosition],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(ours.count == android.count, "\(ours.count) records against Android's \(android.count)",
                sourceLocation: sourceLocation)
        for (index, (mine, theirs)) in zip(ours, android).enumerated() {
            #expect(mine.kind == theirs.kind && abs(mine.x - theirs.x) <= 1 && abs(mine.y - theirs.y) <= 1,
                    "record \(index): \(mine) against Android's \(theirs)", sourceLocation: sourceLocation)
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
        let ours = try Self.ourRecords([
            .runningStitch(length: .number(10)),
            Self.arc(.left, 50, 360),
            Self.arc(.right, 30, 90),
            .moveNSteps(.number(40))
        ])
        try Self.expectWithinOneUnit(ours, decodeRecordPositions(AndroidReference.data("arc_run")))
    }

    @Test("zigzag along an arc matches the Android export")
    func androidArcZigzag() throws {
        let ours = try Self.ourRecords([
            .zigZagStitch(length: .number(2), width: .number(10)),
            Self.arc(.right, 50, 180),
            .moveNSteps(.number(50))
        ])
        try Self.expectWithinOneUnit(ours, decodeRecordPositions(AndroidReference.data("arc_zigzag")))
    }
}
