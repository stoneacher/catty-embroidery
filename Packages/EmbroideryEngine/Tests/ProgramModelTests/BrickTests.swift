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

    /// US-401 added eight more, because the M4 palette needs defaults the
    /// original nine do not cover. Same provenance rule as above: the Catroid
    /// constant is named in the trailing comment, and where Catroid has no
    /// counterpart the absence is stated rather than papered over.
    @Test("the M4 palette defaults match Catroid, or say where Catroid has none")
    func editorBrickDefaultsMatchCatroid() {
        #expect(BrickDefaults.repeatTimes == 10) // REPEAT
        // POINT_IN_DIRECTION, deliberately *not* TURN_DEGREES (15).
        #expect(BrickDefaults.pointInDirection == 90) // POINT_IN_DIRECTION
        // CHANGE_X_BY/CHANGE_Y_BY are their own constants in Catroid and merely
        // happen to equal MOVE_STEPS; they are not the same decision.
        #expect(BrickDefaults.changeXBy == 10) // CHANGE_X_BY
        #expect(BrickDefaults.changeYBy == 10) // CHANGE_Y_BY
        // Catroid has two distinct constants here, both 1d — the same shape as
        // CHANGE_X_BY/CHANGE_Y_BY, so they get two names rather than one.
        #expect(BrickDefaults.setVariableValue == 1.0) // SET_VARIABLE
        #expect(BrickDefaults.changeVariableByValue == 1.0) // CHANGE_VARIABLE
        // No Catroid counterpart: SetVariableBrick(double) seeds only the value
        // and picks the name from a spinner over the project's variables, so ""
        // is the model's honest spelling of "no variable chosen yet".
        #expect(BrickDefaults.variableName.isEmpty)
        // No BrickValues counterpart either: Catroid localises this one
        // (R.string.brick_default_embroidery_file), the same pattern its own
        // closing comment notes for the "Send web request" brick.
        #expect(BrickDefaults.embroideryFileName == "embroidery.dst")
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

    /// A NaN Formula payload stays reflexively equal all the way up the graph
    /// (Brick → Script → Object → Program delegate to Formula's NaN-aware ==),
    /// but the default JSONEncoder refuses to encode it — the M5-deferred
    /// persistence-policy boundary of the new Codable conformance.
    @Test("a NaN Formula payload is reflexive up to Program but does not JSON-encode")
    func nanFormulaPayloadReflexiveButNotEncodable() {
        let brick = Brick.moveNSteps(.number(.nan))
        #expect(brick == brick)
        let program = Program(scenes: [Scene(objects: [Object(scripts: [Script(bricks: [brick])])])])
        #expect(program == program)
        #expect(throws: EncodingError.self) {
            _ = try JSONEncoder().encode(program)
        }
    }
}
