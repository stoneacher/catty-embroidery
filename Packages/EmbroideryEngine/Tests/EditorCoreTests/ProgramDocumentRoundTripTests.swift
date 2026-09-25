import EditorCore
import Foundation
import ProgramModel
import Samples
import Testing

/// US-404 test plan 1–3 and 9: what goes into the document comes back out,
/// asserted as whole-`Program` equality (ADR-006 pattern 3).
@Suite("Program document round trip")
struct ProgramDocumentRoundTripTests {
    // MARK: Fixtures

    /// Every `Brick` case, by construction: each kind's template, concatenated —
    /// except `.loopEnd`'s own, which is a bare `[.loopEnd]` (ADR-035 keeps it
    /// out of the palette, not out of `template()`). The openers' templates
    /// already ship their `loopEnd`s, so the case is still covered and the
    /// program passes the admission check; a round trip that tripped over its
    /// own fixture would prove nothing about the codec.
    static let everyBrick: [Brick] = BrickKind.allCases.filter { $0 != .loopEnd }.flatMap { $0.template() }

    /// Every `Formula` case, and every `BinaryOperator`, with the finite extremes
    /// a `Double` can hold. The shape is deliberately wider than the templates'
    /// `.number`-only payloads, which is why test 2 exists beside test 1.
    static let everyFormula: [Formula] = [
        .number(0),
        .number(-0.0),
        .number(.greatestFiniteMagnitude),
        .number(-.greatestFiniteMagnitude),
        .number(.leastNonzeroMagnitude),
        .number(.leastNormalMagnitude),
        .variable(""),
        .variable("Größe ✂︎"),
        .unaryMinus(.variable("x"))
    ] + BinaryOperator.allCases.map { .binary($0, .number(2), .variable("y")) }

    /// A left-leaning `.binary` chain 64 deep. **Not deeper, deliberately**:
    /// `JSONEncoder` throws `invalidValue` at about 512 JSON nesting levels and
    /// each `Formula` node costs two, so a chain of roughly 250 fails to encode
    /// for a reason that has nothing to do with this story (executed at
    /// planning). Nothing in M4 builds `.binary`; M6's formula editor owns that
    /// ceiling. 64 is deep enough that a codec flattening or truncating the tree
    /// fails the equality, and far enough from the ceiling to stay out of it.
    static let deepFormula: Formula = (1 ... 64).reduce(Formula.number(0)) { tree, level in
        .binary(BinaryOperator.allCases[level % BinaryOperator.allCases.count], tree, .number(Double(level)))
    }

    /// Wraps bricks in a program whose every other field is off its default, so
    /// a codec that dropped a field would not be rescued by the initializer
    /// defaults agreeing with the lost value.
    static func program(bricks: [Brick]) -> Program {
        Program(
            name: "Stickerei — every case",
            scenes: [
                Scene(name: "first", objects: [Object(name: "empty")]),
                Scene(name: "second", objects: [
                    Object(
                        name: "needle",
                        startX: -12.5,
                        startY: 40,
                        startHeading: 135,
                        zIndex: 3,
                        variables: [Variable(name: "local", value: -2.25)],
                        scripts: [Script(bricks: [.stitch]), Script(bricks: bricks)]
                    )
                ])
            ],
            variables: [Variable(name: "Side", value: 5), Variable(name: "", value: 1e-300)]
        )
    }

    // MARK: 1–3

    @Test("the fixture really covers every brick kind")
    func everyBrickFixtureIsComplete() {
        #expect(Set(Self.everyBrick.map(BrickKind.init(of:))) == Set(BrickKind.allCases))
    }

    @Test("test plan 1: a program holding every Brick case round-trips unchanged")
    func everyBrickRoundTrips() throws {
        let program = Self.program(bricks: Self.everyBrick + [
            .setThreadColor(hex: "#1A2b3C"),
            .writeEmbroideryToFile(name: "Blüte ⚘.dst")
        ])
        #expect(try ProgramDocument.decode(ProgramDocument.encode(program)) == program)
    }

    @Test("test plan 1: the decoy-shaped editor fixture round-trips unchanged")
    func editorFixtureRoundTrips() throws {
        let program = EditorCoreFixtures.program
        #expect(try ProgramDocument.decode(ProgramDocument.encode(program)) == program)
    }

    @Test("test plan 2: every Formula case round-trips unchanged", arguments: everyFormula + [deepFormula])
    func everyFormulaRoundTrips(_ formula: Formula) throws {
        let program = Self.program(bricks: [
            .moveNSteps(formula),
            .setVariable(name: "v", to: formula),
            .repeatLoop(times: formula),
            .loopEnd
        ])
        #expect(try ProgramDocument.decode(ProgramDocument.encode(program)) == program)
    }

    /// `-0.0 == 0.0`, so whole-value equality cannot see a lost sign. The sign is
    /// asserted on its own.
    @Test("test plan 2: a negative zero keeps its sign")
    func negativeZeroKeepsItsSign() throws {
        let program = Self.program(bricks: [.moveNSteps(.number(-0.0))])
        let decoded = try ProgramDocument.decode(ProgramDocument.encode(program))
        let script = try #require(decoded.scenes.last?.objects.first?.scripts.last)
        guard case let .moveNSteps(.number(value)) = script.bricks.first else {
            Issue.record("expected moveNSteps(.number), got \(script.bricks)")
            return
        }
        #expect(value.sign == .minus)
    }

    @Test("test plan 3: every shipped sample round-trips through the document", arguments: SampleLibrary.all)
    func sampleRoundTrips(_ sample: SampleProgram) throws {
        #expect(try ProgramDocument.decode(ProgramDocument.encode(sample.program)) == sample.program)
    }

    /// The checked-in bytes, not a fresh encoding: this is what ties the new path
    /// to the existing resources rather than to a fixture of its own.
    @Test("test plan 3: every sample's checked-in JSON decodes through the document", arguments: SampleLibrary.all)
    func checkedInSampleDecodes(_ sample: SampleProgram) throws {
        let url = try #require(sample.programJSONURL, "no JSON resource shipped for \(sample.id.rawValue)")
        #expect(try ProgramDocument.decode(Data(contentsOf: url)) == sample.program)
    }

    /// The document's bytes **are** the checked-in resources' bytes: one format,
    /// one encoding, byte for byte (`SampleResourceRegenerationTests` writes them
    /// with the same formatting). Without this, dropping `.sortedKeys` — which
    /// makes key order vary per object — survived (`swift-code-reviewer`).
    @Test("encoding a sample reproduces its checked-in bytes", arguments: SampleLibrary.all)
    func encodeMatchesCheckedInBytes(_ sample: SampleProgram) throws {
        let url = try #require(sample.programJSONURL)
        #expect(try ProgramDocument.encode(sample.program) == Data(contentsOf: url))
    }

    // MARK: The default coder

    /// The public API can still build a non-finite payload (ADR-017 leaves the
    /// model permissive; normalization is at evaluation). The document keeps
    /// the default `.throw` float strategy — one format, one encoding — so this
    /// is a reported failure, never a `"inf"` string in a file.
    @Test("a non-finite payload built through the model API fails to encode, reported", arguments: [
        Double.infinity, -Double.infinity, Double.nan
    ])
    func nonFinitePayloadFailsToEncode(_ value: Double) {
        let program = Self.program(bricks: [.moveNSteps(.number(value))])
        #expect(throws: ProgramDocumentError.encodingFailed) {
            _ = try ProgramDocument.encode(program)
        }
    }

    // MARK: 9 — the exit test

    /// **Asserts `.success`** (ADR-032 invariant 2, US-211's lesson): for a story
    /// that replaces a failure with a guard, a test asserting the failure passes
    /// while the bug is present. This one is red if the parser lets any
    /// non-finite value through, because the program it builds then throws on
    /// encode.
    ///
    /// The corpus mixes accepted and rejected entries on purpose; the exact
    /// accepted count keeps the test from passing vacuously on a parser that
    /// rejects everything.
    @Test("test plan 9: a program built only from parser-accepted literals encodes and comes back")
    func parserAcceptedLiteralsAlwaysEncode() throws {
        let corpus = [
            "0", "10", "-5", "3.25", ".5", "1.", "1e5",
            "1.7976931348623157e308", "-1.7976931348623157e308", "5e-324", "1e-400",
            "1e400", "-1e400", String(repeating: "9", count: 310), "inf", "nan", "0x1p3"
        ]
        let accepted = corpus.compactMap { try? FormulaLiteral.parse($0).get() }
        #expect(accepted.count == 11)

        let program = Self.program(bricks: accepted.map(Brick.moveNSteps))
        let data = try #require(try? ProgramDocument.encode(program), "an accepted literal failed to encode")
        #expect(try ProgramDocument.decode(data) == program)
    }
}
