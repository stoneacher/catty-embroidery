import EditorCore
import EmbroideryEngine
import Foundation
import Interpreter
import ProgramModel
import Testing

/// Brick backend PR 1, Codex handover round 1: the new formula vocabulary
/// end to end, and its malformed shapes at the document boundary. Each piece was
/// tested on its own (codec, evaluator, sensors); these join them.
@Suite("Formula vocabulary through the document")
struct FormulaVocabularyDocumentTests {
    // MARK: - Saved document → interpreter → DST bytes

    private static func program(_ bricks: [Brick]) -> Program {
        Program(name: "vocabulary", scenes: [Scene(objects: [Object(scripts: [Script(bricks: bricks)])])])
    }

    /// Every function and sensor here evaluates to an exactly representable
    /// value, so the program must stitch byte for byte like its literal twin.
    static let withFunctions = program([
        .runningStitch(length: .unaryFunction(.round, .number(2.5))),
        .placeAt(x: .binaryFunction(.max, .number(10), .number(-4)), y: .unaryFunction(.sqrt, .number(16))),
        .moveNSteps(.sensor(.objectX)),
        .pointInDirection(.binaryFunction(.arctan2, .number(1), .number(0))),
        .moveNSteps(.binaryFunction(.mod, .number(-7), .number(30))),
        .stitch
    ])

    static let withLiterals = program([
        .runningStitch(length: .number(3)),
        .placeAt(x: .number(10), y: .number(4)),
        .moveNSteps(.number(10)),
        .pointInDirection(.number(90)),
        .moveNSteps(.number(23)),
        .stitch
    ])

    private static func dstBytes(_ program: Program) throws -> Data {
        var interpreter = Interpreter(program: program, clock: InterpreterClock(tickDelta: 0.05))
        _ = interpreter.run(maxTicks: 1000)
        return try DSTFile(stream: interpreter.assembledStream(), name: "vocabulary").data
    }

    @Test("a saved program using functions and sensors stitches like its literal twin")
    func endToEnd() throws {
        let reopened = try ProgramDocument.decode(ProgramDocument.encode(Self.withFunctions))
        #expect(reopened == Self.withFunctions)
        let bytes = try Self.dstBytes(reopened)
        #expect(try bytes == (Self.dstBytes(Self.withLiterals)))
        // 512-byte header plus records: a run that stitched nothing would also
        // match its twin, so the design must actually hold stitches.
        #expect(bytes.count > 512 + 3 * 10)
    }

    // MARK: - Malformed new shapes are corrupt, not a trap

    private static let valid = program([
        .setVariable(name: "a", to: .unaryFunction(.sin, .number(30))),
        .setVariable(name: "b", to: .binaryFunction(.mod, .number(7), .number(3))),
        .setVariable(name: "c", to: .constant(.pi))
    ])

    private static var validText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(valid)) ?? Data()
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    static let malformed: [(label: String, text: String)] = [
        ("a binary function without its second argument",
         validText.replacingOccurrences(of: #","_2":{"number":{"_0":3}}"#, with: "")),
        ("an unknown function", validText.replacingOccurrences(of: #""sin":{}"#, with: #""rand":{}"#)),
        ("two formula cases in one node", validText.replacingOccurrences(
            of: #"{"constant":{"_0":{"pi":{}}}}"#,
            with: #"{"constant":{"_0":{"pi":{}}},"sensor":{"_0":{"objectX":{}}}}"#
        )),
        ("an unknown sensor", validText.replacingOccurrences(of: #""pi":{}"#, with: #""objectZ":{}"#))
    ]

    /// Each fixture must really be edited, or its case degrades into "a valid
    /// file decodes" and proves nothing.
    @Test("the malformed fixtures are edits of a valid document")
    func fixturesAreEdited() throws {
        _ = try ProgramDocument.decode(Data(Self.validText.utf8))
        for (label, text) in Self.malformed {
            #expect(text != Self.validText, "\(label) was not edited")
        }
    }

    @Test("a malformed new formula shape is corrupt", arguments: malformed.map(\.label))
    func malformedIsCorrupt(_ label: String) throws {
        let text = try #require(Self.malformed.first { $0.label == label }).text
        #expect(throws: ProgramDocumentError.corrupt) {
            _ = try ProgramDocument.decode(Data(text.utf8))
        }
    }
}
