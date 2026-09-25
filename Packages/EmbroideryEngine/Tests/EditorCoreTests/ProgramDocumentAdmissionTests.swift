import EditorCore
import Foundation
import ProgramModel
import Testing

/// US-404 test plan 4, 5 and 5b: what the document refuses, and with which
/// reason. The document is the third door into the app beside a sample and the
/// blank program, and everything behind that door assumes it received a
/// balanced, current-version program.
///
/// Refused payloads are built with a **raw `JSONEncoder`** and, where needed, a
/// `JSONSerialization` edit — never through `ProgramDocument.encode`, which
/// refuses them too. That is also the honest model of the input: a file
/// somebody edited by hand, or one a later version of the app wrote.
@Suite("Program document admission")
struct ProgramDocumentAdmissionTests {
    // MARK: Payload builders

    private static func rawJSON(_ program: Program) throws -> Data {
        try JSONEncoder().encode(program)
    }

    /// The raw encoding of `program` with top-level keys overwritten.
    private static func rawJSON(_ program: Program, overriding overrides: [String: Any]) throws -> Data {
        var object = try #require(
            try JSONSerialization.jsonObject(with: rawJSON(program)) as? [String: Any]
        )
        for (key, value) in overrides {
            #expect(object[key] != nil, "fixture must contain the key it overrides")
            object[key] = value
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    /// The decoy-shaped editor fixture with its **real** script — scene 1,
    /// object 2, script 1 — replaced. Every earlier hop holds a balanced decoy,
    /// so an admission check that stops at the first scene, object or script
    /// passes this fixture while the bad script sits behind it.
    private static func editorFixture(withRealScript bricks: [Brick]) -> Program {
        EditorCoreFixtures.expecting(bricks)
    }

    // MARK: 4 — the version floor

    @Test("test plan 4: a version-2 payload of an otherwise valid program is refused as unsupported")
    func versionTwoIsUnsupported() throws {
        let data = try Self.rawJSON(EditorCoreFixtures.program, overriding: ["formatVersion": 2])
        #expect(throws: ProgramDocumentError.unsupportedVersion(2)) {
            _ = try ProgramDocument.decode(data)
        }
    }

    /// A later format is free to change shape. The version is read **before** the
    /// shape, or this file is reported as corrupt — exactly the distinction the
    /// version case exists to make.
    @Test("test plan 4: a version-2 payload whose shape v1 cannot read is still unsupported, not corrupt")
    func versionTwoWithNewShapeIsUnsupported() throws {
        let data = try Self.rawJSON(
            EditorCoreFixtures.program,
            overriding: ["formatVersion": 2, "scenes": "a shape from the future"]
        )
        #expect(throws: ProgramDocumentError.unsupportedVersion(2)) {
            _ = try ProgramDocument.decode(data)
        }
    }

    @Test("test plan 4: a version-2 payload holding an unbalanced script reports the version")
    func versionTwoIsReportedBeforeBalance() throws {
        let data = try Self.rawJSON(
            Self.editorFixture(withRealScript: [.loopEnd]),
            overriding: ["formatVersion": 2]
        )
        #expect(throws: ProgramDocumentError.unsupportedVersion(2)) {
            _ = try ProgramDocument.decode(data)
        }
    }

    /// Decided at planning (Sebastian, 2026-09-25): the floor is `!= 1`, not the
    /// story's literal `> 1`. No version 0 or negative version was ever written,
    /// so there is nothing to migrate from and nothing to open.
    @Test("test plan 4: a version below 1 is refused as unsupported", arguments: [0, -1])
    func versionBelowOneIsUnsupported(_ version: Int) throws {
        let data = try Self.rawJSON(EditorCoreFixtures.program, overriding: ["formatVersion": version])
        #expect(throws: ProgramDocumentError.unsupportedVersion(version)) {
            _ = try ProgramDocument.decode(data)
        }
    }

    @Test("test plan 4: a version-1 payload decodes to the program it encodes")
    func versionOneDecodes() throws {
        let data = try Self.rawJSON(EditorCoreFixtures.program)
        #expect(try ProgramDocument.decode(data) == EditorCoreFixtures.program)
    }

    // MARK: 5 — corrupt

    static let corruptPayloads: [(label: String, data: Data)] = {
        let valid = (try? JSONEncoder().encode(EditorCoreFixtures.program)) ?? Data()
        let unknownBrick = String(decoding: valid, as: UTF8.self)
            .replacingOccurrences(of: "\"stopRunningStitch\"", with: "\"embroiderAMoon\"")
        let infiniteLiteral = String(decoding: valid, as: UTF8.self)
            .replacingOccurrences(of: "\"value\":5", with: "\"value\":1e400")
        return [
            ("empty", Data()),
            ("not JSON", Data("hello".utf8)),
            ("truncated", valid.prefix(valid.count / 2)),
            ("top-level array", Data("[]".utf8)),
            ("missing formatVersion", Data(#"{"name":"","scenes":[],"variables":[]}"#.utf8)),
            ("formatVersion as a string", Data(#"{"formatVersion":"1","name":"","scenes":[],"variables":[]}"#.utf8)),
            ("unknown brick case", Data(unknownBrick.utf8)),
            // A file cannot admit ∞: `JSONDecoder` refuses the literal, so a
            // hand-edited `1e400` is corrupt rather than an in-memory `+∞`.
            ("non-finite number literal", Data(infiniteLiteral.utf8))
        ]
    }()

    /// The two string-edited payloads must actually have been edited, or their
    /// cases above degrade into "a valid file decodes" and prove nothing.
    @Test("the string-edited corrupt fixtures differ from the valid encoding")
    func corruptFixturesAreEdited() throws {
        let valid = try Self.rawJSON(EditorCoreFixtures.program)
        for label in ["unknown brick case", "non-finite number literal"] {
            let payload = try #require(Self.corruptPayloads.first { $0.label == label })
            #expect(payload.data != valid, "\(label) fixture was not edited")
        }
    }

    @Test("test plan 5: unreadable payloads are corrupt, not a trap", arguments: corruptPayloads.map(\.label))
    func unreadablePayloadIsCorrupt(_ label: String) throws {
        let payload = try #require(Self.corruptPayloads.first { $0.label == label })
        #expect(throws: ProgramDocumentError.corrupt) {
            _ = try ProgramDocument.decode(payload.data)
        }
    }

    // MARK: 5b — balance

    @Test("test plan 5b: a version-1 payload with a stray loopEnd is refused with the reason")
    func strayLoopEndIsRefused() throws {
        let data = try Self.rawJSON(Self.editorFixture(withRealScript: [.stitch, .loopEnd]))
        #expect(throws: ProgramDocumentError.unbalancedScript(.unmatchedLoopEnd(index: 1))) {
            _ = try ProgramDocument.decode(data)
        }
    }

    @Test("test plan 5b: a version-1 payload with an unclosed opener is refused with the reason")
    func unclosedOpenerIsRefused() throws {
        let data = try Self.rawJSON(Self.editorFixture(withRealScript: [
            .stitch, .repeatLoop(times: .number(2)), .moveNSteps(.number(10))
        ]))
        #expect(throws: ProgramDocumentError.unbalancedScript(.unmatchedLoopOpener(index: 1))) {
            _ = try ProgramDocument.decode(data)
        }
    }

    /// The same malformed shape `EditorCoreFixtures.withStrayLoopEnd` gives the
    /// editor suites: until this story, a decoded document could be one.
    @Test("test plan 5b: the editor suites' hand-built malformed program cannot come in through a file")
    func editorMalformedFixtureIsRefused() throws {
        let data = try Self.rawJSON(EditorCoreFixtures.withStrayLoopEnd)
        #expect(throws: ProgramDocumentError.unbalancedScript(.unmatchedLoopEnd(index: 0))) {
            _ = try ProgramDocument.decode(data)
        }
    }

    @Test("test plan 5b: the balanced counterpart decodes")
    func balancedCounterpartDecodes() throws {
        let program = Self.editorFixture(withRealScript: [
            .stitch, .repeatLoop(times: .number(2)), .moveNSteps(.number(10)), .loopEnd
        ])
        #expect(try ProgramDocument.decode(Self.rawJSON(program)) == program)
    }

    // MARK: Encode refuses what decode refuses

    /// Decided at planning (Sebastian, 2026-09-25): `encode` returning `Data`
    /// means `decode` accepts it. Otherwise an autosave could write a file the
    /// next launch refuses and renames aside — the blank page the story's user
    /// sentence forbids.
    @Test("encode refuses an unbalanced program with the same reason decode would give")
    func encodeRefusesUnbalanced() {
        #expect(throws: ProgramDocumentError.unbalancedScript(.unmatchedLoopEnd(index: 1))) {
            _ = try ProgramDocument.encode(Self.editorFixture(withRealScript: [.stitch, .loopEnd]))
        }
    }

    @Test("encode refuses a program stamped with a version it would not read back", arguments: [0, 2])
    func encodeRefusesForeignVersion(_ version: Int) {
        var program = EditorCoreFixtures.program
        program.formatVersion = version
        #expect(throws: ProgramDocumentError.unsupportedVersion(version)) {
            _ = try ProgramDocument.encode(program)
        }
    }
}
