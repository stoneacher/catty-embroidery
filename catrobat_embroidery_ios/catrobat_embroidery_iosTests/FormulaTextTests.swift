@testable import catrobat_embroidery_ios
import Foundation
import ProgramModel
import Testing

/// US-407 test-plan item 6: every `Formula` case renders as readable text.
///
/// Exact English strings, with the locale pinned, because "non-empty" would pass a renderer
/// that printed `binary(divide, …)` — and the parenthesisation claims below are claims about
/// *which characters appear*, which only an exact comparison can make.
///
/// The parenthesisation rule is **faithful to the tree**, not minimal: a pair of parentheses
/// is dropped only where the conventional reading gives back the same tree. So `1 − (2 − 3)`
/// keeps its parentheses (dropping them reads as `(1 − 2) − 3`), and a negated or negative
/// right operand is always bracketed, `1 − (−5)`, because `1 − −5` is the kind of string a
/// child reads as a typo.
struct FormulaTextTests {
    private static let english = Locale(identifier: "en_US")

    private static func text(_ formula: Formula) -> String {
        FormulaText.text(for: formula, locale: english)
    }

    private static let varA = Formula.variable("a")
    private static let varB = Formula.variable("b")

    private static func n(_ value: Double) -> Formula {
        .number(value)
    }

    // MARK: - Leaves

    @Test("a number renders without a trailing fraction, and keeps a real one")
    func numbers() {
        #expect(Self.text(Self.n(8)) == "8")
        #expect(Self.text(Self.n(2.5)) == "2.5")
        #expect(Self.text(Self.n(0)) == "0")
    }

    /// No grouping: the `%lld` counts in brick labels print `1000`, and a formula's own number
    /// printing `1,000` beside them would be two spellings of one value on one screen.
    @Test("a large number is not grouped")
    func noGrouping() {
        #expect(Self.text(Self.n(1000)) == "1000")
    }

    /// U+2212, not the formatter's hyphen-minus: VoiceOver reads the minus sign as "minus" and a
    /// hyphen inconsistently, and the operator below uses the same glyph.
    @Test("a negative number uses the minus sign")
    func negativeNumber() {
        #expect(Self.text(Self.n(-5)) == "\u{2212}5")
    }

    @Test("the decimal separator follows the locale")
    func decimalSeparatorFollowsLocale() {
        #expect(FormulaText.text(for: Self.n(2.5), locale: Locale(identifier: "de_DE")) == "2,5")
    }

    @Test("a variable renders as its name, verbatim")
    func variable() {
        #expect(Self.text(.variable("Inner Loop")) == "Inner Loop")
    }

    /// `BrickDefaults.variableName` is `""`, so every Set Variable brick the palette adds shows
    /// this until the user picks a variable. An empty string would render "Set  to 1".
    @Test("an unnamed variable renders a placeholder, not nothing")
    func unnamedVariable() {
        #expect(Self.text(.variable("")) == "(no variable)")
    }

    // MARK: - Operators

    @Test("each binary operator renders infix with its own glyph", arguments: BinaryOperator.allCases)
    func binaryOperators(_ operation: BinaryOperator) {
        let glyph = switch operation {
        case .plus: "+"
        case .minus: "\u{2212}"
        case .mult: "×"
        case .divide: "÷"
        case .pow: "^"
        }
        #expect(Self.text(.binary(operation, Self.n(1), Self.n(2))) == "1 \(glyph) 2")
    }

    /// The case `OctagonRosette` puts on screen the first time anyone opens it.
    @Test("360 ÷ Inner Loop")
    func theRosettesTurn() {
        #expect(Self.text(.binary(.divide, Self.n(360), .variable("Inner Loop"))) == "360 ÷ Inner Loop")
    }

    @Test("unary minus over a leaf needs no parentheses")
    func unaryMinusOverALeaf() {
        #expect(Self.text(.unaryMinus(Self.varA)) == "\u{2212}a")
    }

    /// The story names this one: dropping the parentheses changes the meaning.
    @Test("unary minus over a sum keeps the parentheses")
    func unaryMinusOverASum() {
        #expect(Self.text(.unaryMinus(.binary(.plus, Self.varA, Self.varB))) == "\u{2212}(a + b)")
    }

    @Test("unary minus over a power keeps the parentheses")
    func unaryMinusOverAPower() {
        #expect(Self.text(.unaryMinus(.binary(.pow, Self.varA, Self.n(2)))) == "\u{2212}(a ^ 2)")
    }

    @Test("a double negation is bracketed rather than reading as one symbol")
    func doubleNegation() {
        #expect(Self.text(.unaryMinus(.unaryMinus(Self.varA))) == "\u{2212}(\u{2212}a)")
        #expect(Self.text(.unaryMinus(Self.n(-5))) == "\u{2212}(\u{2212}5)")
    }

    // MARK: - Precedence

    @Test("a lower-precedence left operand is bracketed; a higher one is not")
    func precedence() {
        #expect(Self.text(.binary(.mult, .binary(.plus, Self.n(1), Self.n(2)), Self.n(3))) == "(1 + 2) × 3")
        #expect(Self.text(.binary(.plus, Self.n(1), .binary(.mult, Self.n(2), Self.n(3)))) == "1 + 2 × 3")
    }

    @Test("left-associative operators bracket an equal-precedence right operand only")
    func leftAssociativity() {
        #expect(Self
            .text(.binary(.minus, Self.n(1), .binary(.minus, Self.n(2), Self.n(3)))) == "1 \u{2212} (2 \u{2212} 3)")
        #expect(Self
            .text(.binary(.minus, .binary(.minus, Self.n(1), Self.n(2)), Self.n(3))) == "1 \u{2212} 2 \u{2212} 3")
        #expect(Self.text(.binary(.divide, Self.n(8), .binary(.mult, Self.n(2), Self.n(2)))) == "8 ÷ (2 × 2)")
    }

    @Test("power is right-associative")
    func powerIsRightAssociative() {
        #expect(Self.text(.binary(.pow, Self.n(2), .binary(.pow, Self.n(3), Self.n(2)))) == "2 ^ 3 ^ 2")
        #expect(Self.text(.binary(.pow, .binary(.pow, Self.n(2), Self.n(3)), Self.n(2))) == "(2 ^ 3) ^ 2")
    }

    @Test("a negative base of a power is bracketed")
    func negativeBase() {
        #expect(Self.text(.binary(.pow, Self.n(-5), Self.n(2))) == "(\u{2212}5) ^ 2")
        #expect(Self.text(.binary(.pow, .unaryMinus(Self.varA), Self.n(2))) == "(\u{2212}a) ^ 2")
    }

    @Test("a negated or negative right operand is bracketed")
    func negativeRightOperand() {
        #expect(Self.text(.binary(.minus, Self.n(1), Self.n(-5))) == "1 \u{2212} (\u{2212}5)")
        #expect(Self.text(.binary(.mult, Self.n(2), .unaryMinus(Self.varA))) == "2 × (\u{2212}a)")
    }

    @Test("a negative left operand of a sum needs no parentheses")
    func negativeLeftOperand() {
        #expect(Self.text(.binary(.plus, Self.n(-5), Self.n(1))) == "\u{2212}5 + 1")
    }
}
