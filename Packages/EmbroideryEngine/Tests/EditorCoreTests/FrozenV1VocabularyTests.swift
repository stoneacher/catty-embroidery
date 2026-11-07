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
/// Three alarms, each covering what the others cannot:
/// - **The bytes** (Codex brief round, High). One program holding the whole v1 vocabulary
///   encodes to checked-in bytes, those bytes decode back to it, and decoding then re-encoding
///   reproduces them. That catches key, shape, escaping and number-spelling changes, and a
///   decode that `==` would hide (a lost `-0`, a normalized string).
/// - **The vocabulary**, through test-owned tag enums with exhaustive switches. The production
///   enums' own `allCases` is never the oracle (Codex slice round, High).
/// - **The declarations**, through `Mirror`: struct fields and every enum case's payload, with
///   labels *and* types. An optional field or associated value left `nil`, or an `Int` widened
///   to a `Double`, encodes identically, so only the declaration shows it (swift-code-reviewer,
///   slice 1).
///
/// **The fixture is never regenerated for a format change.** On a mismatch the test writes what
/// it saw to a temporary file, and says whether the difference is presentation only (the same
/// JSON values, spelled differently by a newer Foundation). Only a proven presentation-only
/// difference may replace `FrozenV1.json`, in a journaled, reviewed commit. Anything else is a
/// v2 and goes through ADR-037.
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
            let presentationOnly = (try? JSONValue.sameValues(encoded, frozen)) ?? false
            Issue.record("""
            The v1 bytes changed (\(presentationOnly
                ? "presentation only: same JSON values, spelled differently"
                : "the JSON values differ: this is a format change")). \
            What this build writes is at \(seen.path). \
            Only a presentation-only difference may replace FrozenV1.json, in a journaled commit; \
            a format change is a v2 (ADR-037).
            """)
        }
    }

    @Test("the frozen bytes decode to the maximal v1 program, and re-encode to themselves")
    func frozenBytesDecodeToTheMaximalV1Program() throws {
        let frozen = try Self.frozenBytes()
        let decoded = try ProgramDocument.decode(frozen)
        #expect(decoded == FrozenV1.program)
        #expect(try ProgramDocument.encode(decoded) == frozen)
    }

    /// The root's own defaults. `Program` cannot nest, so the maximal document can't hold an
    /// empty root name or empty `scenes`/`variables`: a coding that omitted those at their
    /// defaults would pass the maximal document alone (Codex handover round 2, High).
    @Test("a program at its root defaults encodes to its own frozen bytes, and back")
    func rootDefaultsMatchFrozenBytes() throws {
        let frozen = try Self.frozenBytes(named: "FrozenV1Root")
        #expect(try ProgramDocument.encode(FrozenV1.rootDefaults) == frozen)
        let decoded = try ProgramDocument.decode(frozen)
        #expect(decoded == FrozenV1.rootDefaults)
        #expect(try ProgramDocument.encode(decoded) == frozen)
    }

    @Test("the maximal program holds every case of the v1 vocabulary")
    func maximalProgramCoversEveryCase() {
        let census = FrozenV1.Census(FrozenV1.program)
        #expect(census.bricks == Set(V1BrickCase.allCases))
        #expect(census.headers == Set(V1HeaderCase.allCases))
        #expect(census.formulas == Set(FormulaCase.allCases))
        #expect(census.operators == Set(V1Operator.allCases))
        #expect(census.unaryFunctions == Set(V1UnaryFunction.allCases))
        #expect(census.binaryFunctions == Set(V1BinaryFunction.allCases))
        #expect(census.constants == Set(V1Constant.allCases))
        #expect(census.sensors == Set(V1Sensor.allCases))
        #expect(census.arcDirections == Set(V1ArcDirection.allCases))
    }

    /// Every formula slot of every brick also holds a nested composite, so a slot whose
    /// coding depended on its payload would show in the bytes (Codex slice round, High).
    @Test("every formula slot holds a composite formula somewhere in the program")
    func everyFormulaSlotHoldsAComposite() {
        let slots = FrozenV1.program.scenes.flatMap(\.objects).flatMap(\.scripts).flatMap(\.bricks)
            .flatMap { brick in
                brick.parameters.compactMap { parameter -> String? in
                    guard case let .formula(formula) = parameter.value, formula == FrozenV1.composite else {
                        return nil
                    }
                    return "\(V1BrickCase(of: brick)).\(parameter.slot)"
                }
            }
        let allSlots = FrozenV1.bricks.flatMap { brick in
            brick.parameters.compactMap { parameter -> String? in
                guard case .formula = parameter.value else { return nil }
                return "\(V1BrickCase(of: brick)).\(parameter.slot)"
            }
        }
        #expect(Set(slots) == Set(allSlots))
    }

    @Test("the program structs hold exactly the v1 stored fields, with their types")
    func structFieldsEqualFrozenV1() throws {
        let program = FrozenV1.program
        let scene = try #require(program.scenes.first)
        let object = try #require(scene.objects.first)
        let script = try #require(object.scripts.first)
        let variable = try #require(program.variables.first)
        #expect(Self.fields(of: program) == [
            "formatVersion: Int", "name: String", "scenes: Array<Scene>", "variables: Array<Variable>"
        ])
        #expect(Self.fields(of: scene) == ["name: String", "objects: Array<Object>"])
        #expect(Self.fields(of: object) == [
            "name: String", "startX: Double", "startY: Double", "startHeading: Double", "zIndex: Int",
            "variables: Array<Variable>", "scripts: Array<Script>"
        ])
        #expect(Self.fields(of: script) == ["header: ScriptHeader", "bricks: Array<Brick>"])
        #expect(Self.fields(of: variable) == ["name: String", "value: Double"])
    }

    /// An associated value added to a case encodes as absent while it is `nil`, so neither the
    /// bytes nor the tag switches see it (swift-code-reviewer, slice 1).
    @Test("every brick and formula case keeps exactly its v1 payload")
    func casePayloadsEqualFrozenV1() {
        let brickSignatures = Set(FrozenV1.bricks.map(Self.payload(of:)))
        #expect(brickSignatures == FrozenV1.brickPayloads)
        let formulaSignatures = Set(FrozenV1.formulas.map(Self.payload(of:)))
        #expect(formulaSignatures == FrozenV1.formulaPayloads)
    }

    // MARK: Helpers

    static func frozenBytes(named name: String = "FrozenV1") throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources"),
            "\(name).json is missing from the test bundle"
        )
        return try Data(contentsOf: url)
    }

    static func fields(of value: Any) -> [String] {
        Mirror(reflecting: value).children.compactMap { child in
            child.label.map { "\($0): \(type(of: child.value))" }
        }
    }

    /// `case(label: Type, …)` for one enum value; a bare `case` when it has no payload.
    static func payload(of value: Any) -> String {
        guard let child = Mirror(reflecting: value).children.first, let name = child.label else {
            return "\(value)"
        }
        let payload = Mirror(reflecting: child.value)
        guard payload.displayStyle == .tuple else {
            return "\(name)(_: \(type(of: child.value)))"
        }
        let parts = payload.children.map { element in
            let label = element.label.map { $0.hasPrefix(".") ? "_" : $0 } ?? "_"
            return "\(label): \(type(of: element.value))"
        }
        return "\(name)(\(parts.joined(separator: ", ")))"
    }
}

// MARK: - Semantic JSON comparison, for the mismatch message

enum JSONValue {
    /// Whether two documents hold the same JSON values: the same keys, the same strings scalar
    /// for scalar, and the same numbers bit for bit. Spacing, key order and number spelling are
    /// presentation.
    static func sameValues(_ lhs: Data, _ rhs: Data) throws -> Bool {
        try same(JSONSerialization.jsonObject(with: lhs), JSONSerialization.jsonObject(with: rhs))
    }

    private static func same(_ lhs: Any, _ rhs: Any) -> Bool {
        switch (lhs, rhs) {
        case let (lhs as [String: Any], rhs as [String: Any]):
            Set(lhs.keys) == Set(rhs.keys) && lhs.allSatisfy { key, value in same(value, rhs[key] as Any) }
        case let (lhs as [Any], rhs as [Any]):
            lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { same($0, $1) }
        case let (lhs as String, rhs as String):
            Array(lhs.unicodeScalars) == Array(rhs.unicodeScalars)
        case let (lhs as NSNumber, rhs as NSNumber):
            lhs.doubleValue.bitPattern == rhs.doubleValue.bitPattern
        case (is NSNull, is NSNull):
            true
        default:
            false
        }
    }
}
