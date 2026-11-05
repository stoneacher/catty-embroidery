import EditorCore
import Foundation
import ProgramModel
import Testing

/// The program format v1, frozen (US-331, ADR-037 amendment of 2026-11-05).
///
/// Once a build has left the developer's devices, an older reader will meet files written by
/// newer builds. Anything that changes what v1 bytes look like must therefore bump
/// `Program.currentFormatVersion` and build ADR-037's three admission operations, or the older
/// reader reports a newer file as `.corrupt` instead of `.unsupportedVersion`.
///
/// **The oracle is the bytes, not the keys** (Codex brief round, High). A key census misses
/// same-key changes an old reader misparses: a no-payload case's `{}` becoming `null`, a raw
/// value or a custom `Codable`, a default field left out, a number written differently. A round
/// trip only proves that the *new* writer and the *new* reader agree. So one program that holds
/// the whole v1 vocabulary is encoded and compared with checked-in bytes, and those bytes must
/// decode back to it.
///
/// **The fixture is never regenerated.** On a mismatch the test writes what it saw to a
/// temporary file for diagnosis. Copying that over `FrozenV1.json` would un-freeze the format,
/// so a change that needs new bytes is a v2 and goes through ADR-037.
@Suite("Program format v1 is frozen")
struct FrozenV1VocabularyTests {
    @Test("encoding the maximal v1 program gives exactly the frozen bytes")
    func encodingTheMaximalV1ProgramMatchesFrozenBytes() throws {
        let frozen = try Self.frozenBytes()
        let encoded = try ProgramDocument.encode(FrozenV1.program)
        if encoded != frozen {
            let seen = FileManager.default.temporaryDirectory
                .appendingPathComponent("FrozenV1-seen-\(UUID().uuidString).json")
            try? encoded.write(to: seen)
            Issue.record("""
            The v1 wire format changed. What this build writes is at \(seen.path). \
            Do not copy it over FrozenV1.json: a format change is a v2 (ADR-037).
            """)
        }
    }

    @Test("the frozen bytes decode to the maximal v1 program")
    func frozenBytesDecodeToTheMaximalV1Program() throws {
        #expect(try ProgramDocument.decode(Self.frozenBytes()) == FrozenV1.program)
    }

    @Test("the maximal program holds every case of the v1 vocabulary")
    func maximalProgramCoversEveryCase() {
        let census = FrozenV1.Census(FrozenV1.program)
        #expect(census.bricks == Set(V1BrickCase.allCases))
        #expect(census.headers == Set(V1HeaderCase.allCases))
        #expect(census.formulas == Set(FormulaCase.allCases))
        #expect(census.operators == Set(BinaryOperator.allCases.map { "\($0)" }))
        #expect(census.unaryFunctions == Set(UnaryFunction.allCases))
        #expect(census.binaryFunctions == Set(BinaryFunction.allCases))
        #expect(census.constants == Set(FormulaConstant.allCases))
        #expect(census.sensors == Set(Sensor.allCases))
        #expect(census.arcDirections == Set(ArcDirection.allCases))
    }

    /// A secondary alarm: a new stored field that encodes as absent (an optional left `nil`)
    /// would leave the frozen bytes unchanged. `Mirror` sees stored properties, which is the
    /// one thing the byte comparison cannot.
    @Test("the program structs hold exactly the v1 stored fields")
    func structFieldLabelsEqualFrozenV1() throws {
        let program = FrozenV1.program
        let scene = try #require(program.scenes.first)
        let object = try #require(scene.objects.first)
        let script = try #require(object.scripts.first)
        let variable = try #require(program.variables.first)
        #expect(Self.labels(of: program) == ["formatVersion", "name", "scenes", "variables"])
        #expect(Self.labels(of: scene) == ["name", "objects"])
        #expect(Self.labels(of: object) == [
            "name", "startX", "startY", "startHeading", "zIndex", "variables", "scripts"
        ])
        #expect(Self.labels(of: script) == ["header", "bricks"])
        #expect(Self.labels(of: variable) == ["name", "value"])
    }

    // MARK: Helpers

    static func frozenBytes() throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: "FrozenV1", withExtension: "json", subdirectory: "Resources"),
            "FrozenV1.json is missing from the test bundle"
        )
        return try Data(contentsOf: url)
    }

    static func labels(of value: Any) -> [String] {
        Mirror(reflecting: value).children.compactMap(\.label)
    }
}

// MARK: - The v1 vocabulary, by exhaustive switch

/// One tag per `Brick` case. `init(of:)` has no `default:`, so a new `Brick` case does not
/// compile here until it gets a tag, and then the census test fails until `FrozenV1.bricks`
/// holds one, which changes the frozen bytes. That is the point: a new brick is a v2.
enum V1BrickCase: CaseIterable {
    case moveNSteps, turnLeft, turnRight, pointInDirection, placeAt, setX, setY, changeXBy, changeYBy
    case arc, goThrough
    case repeatLoop, forever, repeatUntil, forVariableFromTo, loopEnd
    case wait, waitUntil, ifThen, ifElse, elseBranch, ifEnd
    case setVariable, changeVariableBy
    case stitch, setThreadColor, runningStitch, zigZagStitch, tripleStitch, sewUp, stopRunningStitch
    case writeEmbroideryToFile

    init(of brick: Brick) {
        switch brick {
        case .moveNSteps: self = .moveNSteps
        case .turnLeft: self = .turnLeft
        case .turnRight: self = .turnRight
        case .pointInDirection: self = .pointInDirection
        case .placeAt: self = .placeAt
        case .setX: self = .setX
        case .setY: self = .setY
        case .changeXBy: self = .changeXBy
        case .changeYBy: self = .changeYBy
        case .arc: self = .arc
        case .goThrough: self = .goThrough
        case .repeatLoop: self = .repeatLoop
        case .forever: self = .forever
        case .repeatUntil: self = .repeatUntil
        case .forVariableFromTo: self = .forVariableFromTo
        case .loopEnd: self = .loopEnd
        case .wait: self = .wait
        case .waitUntil: self = .waitUntil
        case .ifThen: self = .ifThen
        case .ifElse: self = .ifElse
        case .elseBranch: self = .elseBranch
        case .ifEnd: self = .ifEnd
        case .setVariable: self = .setVariable
        case .changeVariableBy: self = .changeVariableBy
        case .stitch: self = .stitch
        case .setThreadColor: self = .setThreadColor
        case .runningStitch: self = .runningStitch
        case .zigZagStitch: self = .zigZagStitch
        case .tripleStitch: self = .tripleStitch
        case .sewUp: self = .sewUp
        case .stopRunningStitch: self = .stopRunningStitch
        case .writeEmbroideryToFile: self = .writeEmbroideryToFile
        }
    }
}

/// One tag per `ScriptHeader` case, for the same reason as `V1BrickCase`.
enum V1HeaderCase: CaseIterable {
    case whenStarted

    init(of header: ScriptHeader) {
        switch header {
        case .whenStarted: self = .whenStarted
        }
    }
}

// MARK: - The maximal v1 program

enum FrozenV1 {
    /// Every formula shape v1 can hold, each leaf enum through `allCases`. Payloads are
    /// deliberately varied (negative zero, a subnormal, the largest finite value, non-ASCII
    /// names) so the frozen bytes also pin how numbers and strings are written.
    static let formulas: [Formula] = [
        .number(0.1),
        .number(-0.0),
        .number(.leastNonzeroMagnitude),
        .number(.greatestFiniteMagnitude),
        .number(-12),
        .variable("Größe ✂︎"),
        .unaryMinus(.variable("i")),
        .logicalNot(.constant(.false))
    ]
        + BinaryOperator.allCases.map { .binary($0, .number(2), .variable("v")) }
        + UnaryFunction.allCases.map { .unaryFunction($0, .number(0.5)) }
        + BinaryFunction.allCases.map { .binaryFunction($0, .number(7), .sensor(.objectY)) }
        + FormulaConstant.allCases.map(Formula.constant)
        + Sensor.allCases.map(Formula.sensor)

    /// Every brick case, with each opener closed so the document admits the script.
    static let bricks: [Brick] = [
        .moveNSteps(.number(10)),
        .turnLeft(.number(15)),
        .turnRight(.number(-15)),
        .pointInDirection(.number(90)),
        .placeAt(x: .number(-100), y: .number(100.5)),
        .setX(.number(1)),
        .setY(.number(2)),
        .changeXBy(.number(3)),
        .changeYBy(.number(4)),
        .arc(direction: .left, radius: .number(30), degrees: .number(90)),
        .arc(direction: .right, radius: .number(20), degrees: .number(180)),
        .goThrough(throughX: .number(5), throughY: .number(6), x: .number(7), y: .number(8)),
        .repeatLoop(times: .number(3)),
        .forever,
        .loopEnd,
        .loopEnd,
        .repeatUntil(condition: .binary(.greaterThan, .variable("v"), .number(5))),
        .forVariableFromTo(name: "i", from: .number(1), to: .number(4)),
        .loopEnd,
        .loopEnd,
        .wait(seconds: .number(0.25)),
        .waitUntil(condition: .constant(.true)),
        .ifThen(condition: .constant(.true)),
        .ifElse(condition: .constant(.false)),
        .elseBranch,
        .ifEnd,
        .ifEnd,
        .changeVariableBy(name: "v", value: .number(-1)),
        .stitch,
        .setThreadColor(hex: "#1A2b3C"),
        .runningStitch(length: .number(2)),
        .zigZagStitch(length: .number(2), width: .number(3)),
        .tripleStitch(length: .number(2.5)),
        .sewUp,
        .stopRunningStitch,
        .writeEmbroideryToFile(name: "Blüte ⚘.dst")
    ] + formulas.map { .setVariable(name: "v", to: $0) }

    static let program = Program(
        name: "Frozen v1 — every case",
        scenes: [
            Scene(name: "scene", objects: [
                Object(
                    name: "needle",
                    startX: -12.5,
                    startY: 40,
                    startHeading: 135,
                    zIndex: 3,
                    variables: [Variable(name: "local", value: -2.25)],
                    scripts: [Script(header: .whenStarted, bricks: bricks)]
                )
            ])
        ],
        variables: [Variable(name: "v", value: 5), Variable(name: "i", value: 1e-300)]
    )

    /// What the program actually holds, collected by walking it, so the coverage claim is
    /// observed rather than restated.
    struct Census {
        var bricks: Set<V1BrickCase> = []
        var headers: Set<V1HeaderCase> = []
        var formulas: Set<FormulaCase> = []
        var operators: Set<String> = []
        var unaryFunctions: Set<UnaryFunction> = []
        var binaryFunctions: Set<BinaryFunction> = []
        var constants: Set<FormulaConstant> = []
        var sensors: Set<Sensor> = []
        var arcDirections: Set<ArcDirection> = []

        init(_ program: Program) {
            for script in program.scenes.flatMap(\.objects).flatMap(\.scripts) {
                headers.insert(V1HeaderCase(of: script.header))
                for brick in script.bricks {
                    bricks.insert(V1BrickCase(of: brick))
                    if case let .arc(direction, _, _) = brick {
                        arcDirections.insert(direction)
                    }
                    for parameter in brick.parameters {
                        if case let .formula(formula) = parameter.value {
                            visit(formula)
                        }
                    }
                }
            }
        }

        private mutating func visit(_ formula: Formula) {
            formulas.insert(FormulaCase(of: formula))
            switch formula {
            case .number, .variable: break
            case let .binary(op, lhs, rhs):
                operators.insert("\(op)")
                visit(lhs)
                visit(rhs)
            case let .unaryMinus(operand), let .logicalNot(operand): visit(operand)
            case let .unaryFunction(function, argument):
                unaryFunctions.insert(function)
                visit(argument)
            case let .binaryFunction(function, first, second):
                binaryFunctions.insert(function)
                visit(first)
                visit(second)
            case let .constant(constant): constants.insert(constant)
            case let .sensor(sensor): sensors.insert(sensor)
            }
        }
    }
}
