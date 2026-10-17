@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Testing

/// Brick backend slice 1: function calls, `pi` and sensors render as readable
/// text, and their lock reasons resolve.
///
/// Names are Catroid's own formula-editor strings (`formula_editor_function_sin`
/// is "sine", `formula_editor_object_x` is "position x"), so a program reads the
/// same on both platforms. A call is a leaf: its own parentheses group the
/// arguments, so it is never bracketed again as an operand.
struct FormulaFunctionTextTests {
    private static let english = Locale(identifier: "en_US")

    private static func text(_ formula: Formula) -> String {
        FormulaText.text(for: formula, locale: english)
    }

    @Test("a unary call renders as name(argument)")
    func unaryCall() {
        #expect(Self.text(.unaryFunction(.sin, .number(30))) == "sine(30)")
        #expect(Self.text(.unaryFunction(.sqrt, .binary(.plus, .variable("a"), .number(1))))
            == "square root(\"a\" + 1)")
    }

    @Test("a binary call renders its two arguments in order")
    func binaryCall() {
        #expect(Self.text(.binaryFunction(.mod, .variable("i"), .number(4))) == "modulo(\"i\", 4)")
        #expect(Self.text(.binaryFunction(.arctan2, .number(1), .number(-2))) == "arctangent2(1, \u{2212}2)")
    }

    @Test("pi and the sensors render as Catroid names them")
    func constantAndSensors() {
        #expect(Self.text(.constant(.pi)) == "pi")
        #expect(Self.text(.sensor(.objectX)) == "position x")
        #expect(Self.text(.sensor(.objectY)) == "position y")
        #expect(Self.text(.sensor(.motionDirection)) == "motion direction")
    }

    @Test("a call is a leaf: never bracketed as an operand")
    func callIsLeaf() {
        let call = Formula.unaryFunction(.cos, .number(60))
        #expect(Self.text(.binary(.mult, .number(2), call)) == "2 × cosine(60)")
        #expect(Self.text(.binary(.pow, call, .number(2))) == "cosine(60) ^ 2")
        #expect(Self.text(.unaryMinus(call)) == "\u{2212}cosine(60)")
    }

    /// Exact, per case: "distinct and resolved" below would pass a swapped pair
    /// such as min ↔ max.
    @Test("every function renders under its own Catroid name")
    func everyFunctionName() {
        let unary: [UnaryFunction: String] = [
            .sin: "sine", .cos: "cosine", .tan: "tangent", .arcsin: "arcsine", .arccos: "arccosine",
            .arctan: "arctangent", .sqrt: "square root", .abs: "absolute value", .round: "round",
            .floor: "floor", .ceil: "ceiling", .ln: "natural logarithm", .log: "decimal logarithm",
            .exp: "exponent"
        ]
        #expect(Set(unary.keys) == Set(UnaryFunction.allCases))
        for (function, name) in unary {
            #expect(Self.text(.unaryFunction(function, .number(1))) == "\(name)(1)")
        }
        let binary: [BinaryFunction: String] = [
            .arctan2: "arctangent2", .min: "minimum of", .max: "maximum of", .mod: "modulo"
        ]
        #expect(Set(binary.keys) == Set(BinaryFunction.allCases))
        for (function, name) in binary {
            #expect(Self.text(.binaryFunction(function, .number(1), .number(2))) == "\(name)(1, 2)")
        }
    }

    /// Every name resolves (a missing catalog entry renders as its key) and no
    /// two functions or sensors share one, so a reader can tell them apart.
    @Test("every function, constant and sensor has its own resolved name")
    func everyNameIsDistinctAndResolved() {
        let names = UnaryFunction.allCases.map { Self.text(.unaryFunction($0, .number(1))) }
            + BinaryFunction.allCases.map { Self.text(.binaryFunction($0, .number(1), .number(2))) }
            + FormulaConstant.allCases.map { Self.text(.constant($0)) }
            + Sensor.allCases.map { Self.text(.sensor($0)) }
        #expect(Set(names).count == names.count)
        for name in names {
            #expect(!name.contains("formula."), "unresolved: \(name)")
        }
    }

    @Test("function and sensor lock reasons resolve and differ from the others")
    func lockReasons() {
        let reasons: [ReadOnlyFormulaReason] = [.binary, .unaryMinus, .function, .sensor]
        let messages = reasons.map { ParameterEditorText.message(for: $0, locale: Self.english) }
        #expect(Set(messages).count == reasons.count)
        for message in messages {
            #expect(!message.hasPrefix("parameter."), "unresolved: \(message)")
        }
    }
}
