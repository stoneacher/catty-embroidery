@testable import catrobat_embroidery_ios
import Foundation
import ProgramModel
import Testing

/// Variables slice 1 (brief D16): comparisons, `and`/`or`/`not` and `true`/`false` render as
/// Catroid's formula editor writes them (`formula_editor_logic_*`, `formula_editor_function_true`).
///
/// The same faithful-to-the-tree rule as arithmetic, with Catroid's precedence
/// (`Operators.java`): `or` binds loosest, then `and`, then comparisons and `not`, then the
/// arithmetic operators. One addition: **a comparison inside a comparison is always
/// bracketed**, so `(1 < 2) = 1` never reads as a chained `1 < 2 = 1`.
struct FormulaLogicTextTests {
    private static let english = Locale(identifier: "en_US")

    private static func text(_ formula: Formula) -> String {
        FormulaText.text(for: formula, locale: english)
    }

    private static let varA = Formula.variable("a")
    private static let varB = Formula.variable("b")
    private static let varC = Formula.variable("c")

    private static func less(_ left: Formula, _ right: Formula) -> Formula {
        .binary(.smallerThan, left, right)
    }

    @Test("true and false render as words")
    func constants() {
        #expect(Self.text(.constant(.true)) == "true")
        #expect(Self.text(.constant(.false)) == "false")
    }

    @Test("not renders as a word before its operand")
    func logicalNot() {
        #expect(Self.text(.logicalNot(Self.varA)) == "not \"a\"")
        #expect(Self.text(.logicalNot(Self.less(Self.varA, .number(2)))) == "not (\"a\" < 2)")
        #expect(Self.text(.logicalNot(.logicalNot(Self.varA))) == "not (not \"a\")")
    }

    @Test("arithmetic inside a comparison needs no parentheses")
    func arithmeticInsideAComparison() {
        #expect(Self.text(Self.less(.binary(.plus, Self.varA, .number(1)), .binary(.mult, Self.varB, .number(2))))
            == "\"a\" + 1 < \"b\" × 2")
    }

    @Test("a comparison inside arithmetic is bracketed")
    func comparisonInsideArithmetic() {
        #expect(Self.text(.binary(.plus, Self.less(Self.varA, Self.varB), .number(1))) == "(\"a\" < \"b\") + 1")
    }

    @Test("a comparison inside a comparison is always bracketed, on either side")
    func comparisonInsideAComparison() {
        #expect(Self.text(.binary(.equal, Self.less(Self.varA, Self.varB), .number(1))) == "(\"a\" < \"b\") = 1")
        #expect(Self.text(.binary(.equal, .number(1), Self.less(Self.varA, Self.varB))) == "1 = (\"a\" < \"b\")")
    }

    @Test("comparisons inside and/or need no parentheses")
    func comparisonsInsideLogic() {
        #expect(Self.text(.binary(.logicalAnd, Self.less(Self.varA, Self.varB), .logicalNot(Self.varC)))
            == "\"a\" < \"b\" and not \"c\"")
    }

    @Test("and binds tighter than or")
    func andBindsTighterThanOr() {
        #expect(Self.text(.binary(.logicalOr, Self.varA, .binary(.logicalAnd, Self.varB, Self.varC)))
            == "\"a\" or \"b\" and \"c\"")
        #expect(Self.text(.binary(.logicalAnd, .binary(.logicalOr, Self.varA, Self.varB), Self.varC))
            == "(\"a\" or \"b\") and \"c\"")
    }

    @Test("and and or associate left, like the arithmetic operators")
    func logicAssociatesLeft() {
        #expect(Self.text(.binary(.logicalAnd, .binary(.logicalAnd, Self.varA, Self.varB), Self.varC))
            == "\"a\" and \"b\" and \"c\"")
        #expect(Self.text(.binary(.logicalAnd, Self.varA, .binary(.logicalAnd, Self.varB, Self.varC)))
            == "\"a\" and (\"b\" and \"c\")")
    }

    @Test("power renders as a call, like the other functions")
    func power() {
        #expect(Self.text(.binaryFunction(.power, .number(2), .number(3))) == "power(2, 3)")
    }
}
