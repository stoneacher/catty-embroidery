import Foundation
import ProgramModel
import Testing

@Suite("Brick enum")
struct BrickTests {
    /// Test plan 4 (bricks): Codable round-trip for bricks with Formula payloads.
    @Test("bricks with Formula and String payloads round-trip through Codable")
    func brickCodableRoundTrip() throws {
        let bricks: [Brick] = [
            .moveNSteps(.number(10)),
            .turnLeft(.number(15)),
            .turnRight(.variable("angle")),
            .pointInDirection(.number(90)),
            .placeAt(x: .number(100), y: .number(200)),
            .setX(.number(-5)),
            .setY(.number(5)),
            .changeXBy(.number(1)),
            .changeYBy(.number(-1)),
            .repeatLoop(times: .number(3)),
            .forever,
            .loopEnd,
            .wait(seconds: .number(1.0)),
            .setVariable(name: "x", to: .binary(.plus, .number(1), .variable("x"))),
            .changeVariableBy(name: "x", value: .number(2)),
            .stitch,
            .setThreadColor(hex: "#ff0000"),
            .runningStitch(length: .number(10)),
            .zigZagStitch(length: .number(2), width: .number(10)),
            .tripleStitch(length: .number(10)),
            .sewUp,
            .stopRunningStitch,
            .writeEmbroideryToFile(name: "design")
        ]
        let data = try JSONEncoder().encode(bricks)
        let decoded = try JSONDecoder().decode([Brick].self, from: data)
        #expect(decoded == bricks)
    }

    @Test("BrickValues defaults match Catroid")
    func brickDefaultsMatchCatroid() {
        // Catroid common/BrickValues.java (AGPL-3.0, values ported verbatim).
        #expect(BrickDefaults.moveSteps == 10) // MOVE_STEPS
        #expect(BrickDefaults.turnDegrees == 15) // TURN_DEGREES
        #expect(BrickDefaults.placeAtX == 100) // X_POSITION
        #expect(BrickDefaults.placeAtY == 200) // Y_POSITION
        #expect(BrickDefaults.stitchLength == 10) // STITCH_LENGTH
        #expect(BrickDefaults.zigZagLength == 2) // ZIGZAG_STITCH_LENGTH
        #expect(BrickDefaults.zigZagWidth == 10) // ZIGZAG_STITCH_WIDTH
        #expect(BrickDefaults.threadColorHex == "#ff0000") // THREAD_COLOR
        #expect(BrickDefaults.waitSeconds == 1.0) // WAIT = 1000 ms → seconds
    }

    /// Test plan 4 (formulas): Codable was deferred from US-202 to here, where
    /// formulas ship embedded under `Program`.
    @Test("a Formula tree round-trips through Codable")
    func formulaCodableRoundTrip() throws {
        let formula: Formula = .binary(
            .plus,
            .unaryMinus(.number(3.5)),
            .binary(.pow, .variable("base"), .number(2))
        )
        let data = try JSONEncoder().encode(formula)
        let decoded = try JSONDecoder().decode(Formula.self, from: data)
        #expect(decoded == formula)
    }
}
