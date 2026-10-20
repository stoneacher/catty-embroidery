import Foundation
import ProgramModel
import Testing

/// Brick backend slice 1: the JSON shape of the formula vocabulary is the file
/// format (ADR-037), so it is pinned as exact text. The synthesized coding keys
/// are the case names, which is why the names themselves are part of the
/// contract and are pinned below too — renaming a case would orphan every file
/// that used it.
@Suite("Formula codable shape")
struct FormulaCodableShapeTests {
    private static func json(_ formula: Formula) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try String(bytes: encoder.encode(formula), encoding: .utf8) ?? "<not UTF-8>"
    }

    /// The existing shape the new cases follow, so the expectations below are
    /// checked against how this encoder really spells an enum.
    @Test("an existing binary node keeps its shape")
    func binaryAnchor() throws {
        #expect(try Self.json(.binary(.divide, .number(1), .number(2)))
            == #"{"binary":{"_0":{"divide":{}},"_1":{"number":{"_0":1}},"_2":{"number":{"_0":2}}}}"#)
    }

    @Test("a unary function call")
    func unaryFunction() throws {
        #expect(try Self.json(.unaryFunction(.sin, .number(30)))
            == #"{"unaryFunction":{"_0":{"sin":{}},"_1":{"number":{"_0":30}}}}"#)
    }

    @Test("a binary function call")
    func binaryFunction() throws {
        #expect(try Self.json(.binaryFunction(.mod, .number(7), .variable("n")))
            == #"{"binaryFunction":{"_0":{"mod":{}},"_1":{"number":{"_0":7}},"_2":{"variable":{"_0":"n"}}}}"#)
    }

    @Test("a constant")
    func constant() throws {
        #expect(try Self.json(.constant(.pi)) == #"{"constant":{"_0":{"pi":{}}}}"#)
    }

    @Test("a sensor")
    func sensor() throws {
        #expect(try Self.json(.sensor(.objectX)) == #"{"sensor":{"_0":{"objectX":{}}}}"#)
    }

    /// Catroid's `Functions` names, lower-cased as its formula strings spell them,
    /// so the planned code.xml importer maps 1:1. `rand` is out of scope (Brick
    /// backend brief D3); `power` joins with the Variables feature (its brief D4).
    @Test("the unary function vocabulary")
    func unaryVocabulary() throws {
        let names = try UnaryFunction.allCases.map { try Self.json(.unaryFunction($0, .number(0))) }
        #expect(names == [
            "sin", "cos", "tan", "arcsin", "arccos", "arctan", "sqrt", "abs", "round", "floor",
            "ceil", "ln", "log", "exp"
        ].map { #"{"unaryFunction":{"_0":{"\#($0)":{}},"_1":{"number":{"_0":0}}}}"# })
    }

    @Test("the binary function vocabulary")
    func binaryVocabulary() throws {
        let names = try BinaryFunction.allCases.map { try Self.json(.binaryFunction($0, .number(0), .number(0))) }
        #expect(names == ["arctan2", "min", "max", "mod", "power"].map {
            #"{"binaryFunction":{"_0":{"\#($0)":{}},"_1":{"number":{"_0":0}},"_2":{"number":{"_0":0}}}}"#
        })
    }

    @Test("the constant and sensor vocabulary")
    func constantAndSensorVocabulary() throws {
        #expect(try FormulaConstant.allCases.map { try Self.json(.constant($0)) }
            == ["pi", "true", "false"].map { #"{"constant":{"_0":{"\#($0)":{}}}}"# })
        #expect(try Sensor.allCases.map { try Self.json(.sensor($0)) } == ["objectX", "objectY", "motionDirection"]
            .map {
                #"{"sensor":{"_0":{"\#($0)":{}}}}"#
            })
    }

    /// Variables slice 1: Catroid's `Operators` names, camel-cased (`SMALLER_OR_EQUAL`
    /// is `smallerOrEqual`), after the five arithmetic ones.
    @Test("the binary operator vocabulary")
    func operatorVocabulary() throws {
        let names = try BinaryOperator.allCases.map { try Self.json(.binary($0, .number(0), .number(0))) }
        #expect(names == [
            "plus", "minus", "mult", "divide", "pow", "equal", "notEqual", "smallerThan", "smallerOrEqual",
            "greaterThan", "greaterOrEqual", "logicalAnd", "logicalOr"
        ].map { #"{"binary":{"_0":{"\#($0)":{}},"_1":{"number":{"_0":0}},"_2":{"number":{"_0":0}}}}"# })
    }

    /// `not` is a unary operator like minus, so it is a case of its own beside `unaryMinus`.
    @Test("a logical not")
    func logicalNot() throws {
        #expect(try Self.json(.logicalNot(.variable("done"))) == #"{"logicalNot":{"_0":{"variable":{"_0":"done"}}}}"#)
    }

    @Test("every new node decodes back to itself", arguments: [
        Formula.unaryFunction(.sqrt, .binary(.plus, .number(1), .variable("x"))),
        .binaryFunction(.arctan2, .sensor(.objectY), .unaryMinus(.constant(.pi))),
        .constant(.pi),
        .sensor(.motionDirection),
        .logicalNot(.binary(.smallerOrEqual, .variable("i"), .constant(.true))),
        .binaryFunction(.power, .number(2), .binary(.logicalOr, .constant(.false), .number(3)))
    ])
    func decodes(_ formula: Formula) throws {
        let data = try JSONEncoder().encode(formula)
        #expect(try JSONDecoder().decode(Formula.self, from: data) == formula)
    }
}

/// Brick backend slice 4: Arc's JSON shape is part of the file format too.
@Suite("Arc codable shape")
struct ArcCodableShapeTests {
    @Test("an arc brick's shape, with the direction as a named case")
    func arcShape() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let brick = Brick.arc(direction: .left, radius: .number(10), degrees: .number(360))
        let json = try String(bytes: encoder.encode(brick), encoding: .utf8)
        #expect(json
            == #"{"arc":{"degrees":{"number":{"_0":360}},"direction":{"left":{}},"radius":{"number":{"_0":10}}}}"#)
        #expect(try JSONEncoder().encode(ArcDirection.right) == Data(#"{"right":{}}"#.utf8))
    }
}

/// Brick backend slice 5: GoThrough's JSON shape.
@Suite("GoThrough codable shape")
struct GoThroughCodableShapeTests {
    @Test("a GoThrough brick's shape")
    func goThroughShape() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let brick = Brick.goThrough(throughX: .number(1), throughY: .number(2), x: .number(3), y: .number(4))
        let json = try String(bytes: encoder.encode(brick), encoding: .utf8)
        #expect(json == #"{"goThrough":{"throughX":{"number":{"_0":1}},"throughY":{"number":{"_0":2}},"#
            + #""x":{"number":{"_0":3}},"y":{"number":{"_0":4}}}}"#)
    }
}
