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
        let text = String(bytes: valid, encoding: .utf8) ?? ""
        let unknownBrick = text
            .replacingOccurrences(of: "\"stopRunningStitch\"", with: "\"embroiderAMoon\"")
        let infiniteLiteral = text
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

    /// The fixtures above all break the **last** scene and object, so an
    /// admission check reading only `suffix(1)` passed them. These break a decoy
    /// at the *first* scene or object instead (`swift-code-reviewer`).
    @Test("5b: an imbalance in the first scene's decoy is refused")
    func firstSceneDecoyImbalanceIsRefused() throws {
        var program = EditorCoreFixtures.program
        program.scenes[0].objects[0].scripts[0].bricks = [.loopEnd]
        #expect(throws: ProgramDocumentError.unbalancedScript(.unmatchedLoopEnd(index: 0))) {
            _ = try ProgramDocument.decode(Self.rawJSON(program))
        }
    }

    @Test("5b: an imbalance in the first object's decoy is refused")
    func firstObjectDecoyImbalanceIsRefused() throws {
        var program = EditorCoreFixtures.program
        program.scenes[1].objects[0].scripts[0].bricks = [.forever]
        #expect(throws: ProgramDocumentError.unbalancedScript(.unmatchedLoopOpener(index: 0))) {
            _ = try ProgramDocument.decode(Self.rawJSON(program))
        }
    }

    /// ADR-037: scene → object → script order, first imbalance wins. Two
    /// imbalances with different reasons, so a reversed traversal names the
    /// other one.
    @Test("5b: of two imbalances, the first in document order is the reason")
    func firstImbalanceInDocumentOrderWins() throws {
        var program = Self.editorFixture(withRealScript: [.stitch, .loopEnd])
        program.scenes[0].objects[0].scripts[0].bricks = [.forever]
        #expect(throws: ProgramDocumentError.unbalancedScript(.unmatchedLoopOpener(index: 0))) {
            _ = try ProgramDocument.decode(Self.rawJSON(program))
        }
    }

    // MARK: Formula depth

    /// A left-leaning `.binary` chain whose deepest path holds exactly `depth`
    /// `Formula` nodes (the leaf counts as one).
    static func chain(depth: Int) -> Formula {
        (1 ..< depth).reduce(Formula.number(0)) { tree, level in
            .binary(.plus, tree, .number(Double(level)))
        }
    }

    static func program(formulaDepth depth: Int) -> Program {
        Program(scenes: [Scene(objects: [Object(scripts: [
            Script(bricks: [.stitch]),
            Script(bricks: [.stitch, .placeAt(x: .number(1), y: chain(depth: depth))])
        ])])])
    }

    /// Decided at review (Sebastian, 2026-09-25): without a cap, the encoder's
    /// failure mode depended on the thread's stack — `.encodingFailed` at ~250
    /// deep on the 8 MB main thread, a **stack-overflow crash** from ~230 on a
    /// cooperative-pool thread — and a hand-edited file at 241–250 decoded but
    /// could never be encoded again. A named cap makes admission deterministic
    /// and keeps "decode accepts ⇔ encode succeeds" true in both directions.
    @Test("a formula at the depth limit round-trips")
    func formulaAtTheLimitRoundTrips() throws {
        #expect(ProgramDocument.maximumFormulaDepth == 128)
        let program = Self.program(formulaDepth: ProgramDocument.maximumFormulaDepth)
        #expect(try ProgramDocument.decode(ProgramDocument.encode(program)) == program)
    }

    @Test("a formula past the depth limit is refused by decode, with the limit")
    func formulaPastTheLimitIsRefusedOnDecode() throws {
        let data = try Self.rawJSON(Self.program(formulaDepth: ProgramDocument.maximumFormulaDepth + 1))
        #expect(throws: ProgramDocumentError.formulaTooDeep(limit: 128)) {
            _ = try ProgramDocument.decode(data)
        }
    }

    @Test("a formula past the depth limit is refused by encode, with the limit")
    func formulaPastTheLimitIsRefusedOnEncode() {
        #expect(throws: ProgramDocumentError.formulaTooDeep(limit: 128)) {
            _ = try ProgramDocument.encode(Self.program(formulaDepth: ProgramDocument.maximumFormulaDepth + 1))
        }
    }

    /// Every formula-carrying brick position is measured, not just the first
    /// payload: a deep formula in `placeAt`'s *second* argument is caught above,
    /// and here in a loop count and a variable assignment.
    @Test("the depth limit applies to every formula-carrying brick", arguments: [
        Brick.repeatLoop(times: chain(depth: 129)),
        Brick.setVariable(name: "v", to: chain(depth: 129)),
        Brick.zigZagStitch(length: .number(1), width: chain(depth: 129))
    ])
    func depthLimitCoversEveryFormulaPosition(_ brick: Brick) {
        let bricks = brick.opensLoop ? [brick, .loopEnd] : [brick]
        let program = Program(scenes: [Scene(objects: [Object(scripts: [Script(bricks: bricks)])])])
        #expect(throws: ProgramDocumentError.formulaTooDeep(limit: 128)) {
            _ = try ProgramDocument.encode(program)
        }
    }

    /// Every chain above leans left, so a depth that counted only the left
    /// operand passed them all (mutation R8 survived). The same chain mirrored.
    @Test("the depth limit applies to a right-leaning chain")
    func depthLimitCoversRightOperands() {
        let deep = (1 ..< 129).reduce(Formula.number(0)) { tree, level in
            .binary(.minus, .number(Double(level)), tree)
        }
        let program = Program(scenes: [Scene(objects: [Object(scripts: [Script(bricks: [.moveNSteps(deep)])])])])
        #expect(throws: ProgramDocumentError.formulaTooDeep(limit: 128)) {
            _ = try ProgramDocument.encode(program)
        }
    }

    /// Codex round 1 (High): the depth check measured the *whole* tree
    /// recursively before comparing, so a tree built iteratively through the
    /// model API overflowed the stack inside admission instead of being refused.
    /// The check is bounded: it stops descending at `maximumFormulaDepth + 1`.
    ///
    /// The fixture is a `static let` **on purpose, and it is never freed**.
    /// Swift releases an indirect enum recursively, so dropping a chain this deep
    /// crashes its owner — measured at ~3 500 nodes on a 512 KB thread, before
    /// any codec code runs. Held for the process's lifetime, the only recursion
    /// left for this test to hit is the one under test. Red under the recursive
    /// check is a crashed test process, not a failed expectation.
    static let hostilelyDeep: Program = {
        var formula = Formula.number(0)
        for _ in 0 ..< 100_000 {
            formula = .unaryMinus(formula)
        }
        return Program(scenes: [Scene(objects: [Object(scripts: [Script(bricks: [.moveNSteps(formula)])])])])
    }()

    @Test("a model-built formula far past the limit is refused without walking all of it")
    func hostileDepthIsRefusedBoundedly() {
        #expect(throws: ProgramDocumentError.formulaTooDeep(limit: 128)) {
            _ = try ProgramDocument.encode(Self.hostilelyDeep)
        }
    }

    /// Codex round 1 (Medium ×2), decided with Sebastian (2026-09-25): past
    /// Foundation's JSON nesting ceiling (512 levels, two per formula node) the
    /// parser refuses the file before the version or the depth can be read, so it
    /// is `.corrupt`. **Pinned, not fixed**: nothing traps, and US-406 sets the
    /// file aside either way — only the reason differs. A pre-scan that
    /// classified it would be a hand-written JSON lexer for a hostile file.
    @Test("a version-1 formula nested past the JSON parser's ceiling is corrupt, not a trap")
    func formulaPastTheParserCeilingIsCorrupt() throws {
        let leaf = #"{"number":{"_0":7}}"#
        let shallow = try String(decoding: Self.rawJSON(Program(scenes: [Scene(objects: [Object(scripts: [
            Script(bricks: [.moveNSteps(.number(7))])
        ])])])), as: UTF8.self)
        #expect(shallow.components(separatedBy: leaf).count == 2, "fixture must hold the leaf exactly once")
        let nested = (0 ..< 300).reduce(leaf) { inner, _ in #"{"unaryMinus":{"_0":"# + inner + "}}" }
        #expect(throws: ProgramDocumentError.corrupt) {
            _ = try ProgramDocument.decode(Data(shallow.replacingOccurrences(of: leaf, with: nested).utf8))
        }
    }

    @Test("a later version nested past the JSON parser's ceiling is corrupt, not a trap")
    func futureShapePastTheParserCeilingIsCorrupt() {
        let arrays = String(repeating: "[", count: 10000) + "0" + String(repeating: "]", count: 10000)
        let data = Data((#"{"formatVersion":2,"future":"# + arrays + "}").utf8)
        #expect(throws: ProgramDocumentError.corrupt) {
            _ = try ProgramDocument.decode(data)
        }
    }

    @Test("the depth limit applies inside a unary minus")
    func depthLimitCoversUnaryMinus() {
        let deep = Formula.unaryMinus(Self.chain(depth: 128))
        let program = Program(scenes: [Scene(objects: [Object(scripts: [Script(bricks: [.moveNSteps(deep)])])])])
        #expect(throws: ProgramDocumentError.formulaTooDeep(limit: 128)) {
            _ = try ProgramDocument.encode(program)
        }
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
