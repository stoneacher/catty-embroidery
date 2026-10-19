@testable import catrobat_embroidery_ios
import Foundation
import ProgramModel
import Testing

/// Variables slice 1 (brief D16): comparisons, `and`/`or`/`not` and `true`/`false` render as
/// Catroid's formula editor writes them (`formula_editor_logic_*`, `formula_editor_function_true`).
///
/// The same faithful-to-the-tree rule as arithmetic, with Catroid's precedence
/// (`Operators.java:28-30`): `or` binds loosest, then `and`, then `=`, then the other
/// comparisons and `not`, then the arithmetic operators. Because `=` and `<` differ there,
/// **any comparison, `not`, `and` or `or` inside a comparison is bracketed**, so the text never
/// depends on that difference: `(1 < 2) = 1` never reads as a chained `1 < 2 = 1`.
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

    /// `"a" and "b" = true` would read as `"a" and ("b" = true)`, since a comparison binds
    /// tighter than `and` (Codex slice review of slice 1).
    @Test("and, or and not inside a comparison are bracketed, on either side")
    func logicInsideAComparison() {
        #expect(Self.text(.binary(.equal, .binary(.logicalAnd, Self.varA, Self.varB), .constant(.true)))
            == "(\"a\" and \"b\") = true")
        #expect(Self.text(.binary(.equal, .constant(.true), .binary(.logicalOr, Self.varA, Self.varB)))
            == "true = (\"a\" or \"b\")")
        #expect(Self.text(.binary(.equal, .logicalNot(Self.varA), .number(1))) == "(not \"a\") = 1")
    }

    /// `not "a" + 1` reads as `not ("a" + 1)` in Catroid, whose `not` binds looser than `+`
    /// (swift-code-reviewer, slice 1).
    @Test("not inside arithmetic or a comparison is bracketed")
    func notInsideArithmetic() {
        #expect(Self.text(.binary(.plus, .logicalNot(Self.varA), .number(1))) == "(not \"a\") + 1")
        #expect(Self.text(Self.less(.logicalNot(Self.varA), Self.varB)) == "(not \"a\") < \"b\"")
    }

    /// A comparison leaves a negative right operand bare, unlike `1 − (−5)`: `"a" < −5` does not
    /// read as a typo, since `<` is not a minus.
    @Test("a negative right operand of a comparison needs no parentheses")
    func negativeRightOfAComparison() {
        #expect(Self.text(Self.less(Self.varA, .number(-5))) == "\"a\" < −5")
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
