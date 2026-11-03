import CatrobatImport
import Foundation
import ProgramModel
import Testing

/// Slice 3, literals: Catroid reads a NUMBER or STRING literal with one of three
/// string conversions depending on where it sits, and keeps it as a string in
/// three places, which are refused (brief D4).
struct FormulaLiteralImportTests: FormulaImportTesting {
    private typealias XML = FormulaXML

    // MARK: - Literals, by context (brief D4)

    /// A brick's number slot: Catroid's `Double.valueOf` (`Formula.java:139-161`),
    /// which trims, accepts `fFdD` suffixes and hex; failure acts as NaN.
    @Test(arguments: [
        ("2", 2.0), (" 2 ", 2), ("1d", 1), ("1.5F", 1.5), ("0x1p3", 8), (".5", 0.5), ("5.", 5), ("1e3", 1000),
        ("+7", 7), ("NaN", .nan), ("-NaN", .nan), ("abc", .nan), ("", .nan), ("#000000", .nan), ("1,5", .nan),
        ("inf", .nan), ("nan", .nan), ("1e", .nan), ("0x1", .nan), ("1 2", .nan),
        ("2.5e-3", 0.0025), ("1E+2", 100), ("\t5\n", 5), ("\u{00A0}5", .nan), ("0X.8P1", 1), ("-0x1p-1", -0.5),
        // Digitless forms: rejected by the grammar and, today, by Swift's parser too.
        (".", .nan), ("e5", .nan), (".e5", .nan), ("0x.p1", .nan), ("0xp1", .nan)
    ])
    func numberSlotLiteral(text: String, expected: Double) throws {
        for type in ["STRING", "NUMBER"] {
            #expect(try formula(XML.node(type, text)) == .number(expected), "\(type) \(text)")
        }
    }

    @Test func negativeZeroLiteralKeepsItsSign() throws {
        #expect(try isNegativeZero(formula(XML.number("-0"))))
        #expect(try isNegativeZero(formula(XML.number("-0.0"))))
    }

    /// `"Infinity"` and `"1e400"` parse to ±∞ in Java, and Catroid keeps the raw
    /// string rather than normalising it to ±MAX, so they are refused everywhere.
    @Test(arguments: ["Infinity", "-Infinity", "1e400", "-1e309"])
    func aNonFiniteLiteralIsRefused(text: String) throws {
        #expect(try blockers(XML.number(text)) == [.nonFiniteLiteral(text)])
        #expect(try blockers(XML.op("PLUS", XML.string(text), XML.number("1"))) == [.nonFiniteLiteral(text)])
    }

    @Test func aMissingValueIsZero() throws {
        #expect(try formula(XML.node("NUMBER")) == .number(0))
        #expect(try formula(XML.node("STRING")) == .number(0))
    }

    /// An empty `<value/>` is the empty string, which no grammar parses.
    @Test func anEmptyValueIsTheEmptyString() throws {
        #expect(try formula(XML.node("STRING", "")) == .number(.nan))
    }

    /// Arithmetic, ordering and logic operands go through `tryInterpretDoubleValue`
    /// (`FormulaElementOperations.kt:79-88`): NaN on failure.
    @Test func operatorOperandsParseOrBecomeNaN() throws {
        #expect(try formula(XML.op("PLUS", XML.string("abc"), XML.number("1"))) == .binary(
            .plus,
            .number(.nan),
            .number(1)
        ))
        #expect(try formula(XML.op("SMALLER_THAN", XML.string("1d"), XML.string("x"))) == .binary(
            .smallerThan,
            .number(1),
            .number(.nan)
        ))
        #expect(try formula(XML.op("MINUS", nil, XML.string("abc"))) == .unaryMinus(.number(.nan)))
    }

    /// `=` and `≠` compare the two strings when either side does not parse
    /// (`FormulaElementOperations.kt:67-75`): refused, since `NaN = NaN` is true
    /// (Codex brief review, finding 1).
    @Test func equalityOperandsParseOrAreRefused() throws {
        #expect(try formula(XML.op("EQUAL", XML.string("1"), XML.number("1"))) == .binary(
            .equal,
            .number(1),
            .number(1)
        ))
        #expect(try formula(XML.op("EQUAL", XML.string("NaN"), XML.number("1"))) == .binary(
            .equal,
            .number(.nan),
            .number(1)
        ))
        #expect(try blockers(XML.op("EQUAL", XML.string("a"), XML.string("b"))) == [.stringValue(.equality)])
        #expect(try blockers(XML.op("EQUAL", XML.string("b"), XML.string("b"))) == [.stringValue(.equality)])
        #expect(try blockers(XML.op("NOT_EQUAL", XML.node("USER_VARIABLE", "v"), XML.string("a"))) ==
            [.stringValue(.equality)])
        let bracketed = XML.node("BRACKET", nil, right: XML.string("a"))
        #expect(try blockers(XML.op("EQUAL", bracketed, XML.number("1"))) == [.stringValue(.equality)])
    }

    /// Function arguments go through `tryParseDouble` (`Conversions.kt:35-44`):
    /// anything containing `fFdD` (so `"Infinity"` too) or unparseable is null,
    /// and a null argument makes the whole call 0.0 (`UnaryFunction.kt`,
    /// `BinaryFunction.kt`). A bracket passes its string through.
    @Test func functionArgumentsParseOrFoldTheCallToZero() throws {
        #expect(try formula(XML.function("SIN", XML.string("abc"))) == .number(0))
        #expect(try formula(XML.function("SIN", XML.string("1d"))) == .number(0))
        #expect(try formula(XML.function("SIN", XML.string("Infinity"))) == .number(0))
        #expect(try formula(XML.function("SIN", XML.string("0x1fp1"))) == .number(0))
        #expect(try formula(XML.function("SIN")) == .number(0))
        #expect(try formula(XML.function("MAX", XML.string("abc"), XML.number("1"))) == .number(0))
        #expect(try formula(XML.function("MAX", XML.number("1"))) == .number(0))
        #expect(try formula(XML.function("LOG", XML.string("100"))) == .unaryFunction(.log, .number(100)))
        #expect(try formula(XML.function("LN", XML.string("NaN"))) == .unaryFunction(.ln, .number(.nan)))
        let bracketed = XML.node("BRACKET", nil, right: XML.string("100"))
        #expect(try formula(XML.function("LOG", bracketed)) == .unaryFunction(.log, .number(100)))
        // The bracket keeps the string a string, so the argument rule applies to it:
        // `"100"` alone cannot tell that from operand parsing (caught by mutation).
        let bracketedText = XML.node("BRACKET", nil, right: XML.string("abc"))
        #expect(try formula(XML.function("SIN", bracketedText)) == .number(0))
        let bracketedSuffix = XML.node("BRACKET", nil, right: XML.string("1d"))
        #expect(try formula(XML.function("SIN", bracketedSuffix)) == .number(0))
        // An argument that is an expression is a Double, never null: no fold.
        let sum = XML.op("PLUS", XML.string("abc"), XML.number("1"))
        #expect(try formula(XML.function("SIN", sum)) == .unaryFunction(
            .sin,
            .binary(.plus, .number(.nan), .number(1))
        ))
        // A unary function ignores a right child (`UnaryFunction.kt` reads args[0]).
        #expect(try formula(XML.function("SIN", XML.number("1"), XML.string("abc"))) == .unaryFunction(
            .sin,
            .number(1)
        ))
    }

    @Test func aNonFiniteFunctionArgumentIsRefused() throws {
        #expect(try blockers(XML.function("SIN", XML.number("1e400"))) == [.nonFiniteLiteral("1e400")])
    }

    /// AssertEquals compares `toString()`s, then `toDouble()`s (`AssertAction.kt:45-50`):
    /// a literal that parses compares numerically; one that does not is a string.
    @Test func assertOperandParsesOrIsRefused() throws {
        #expect(try formula(XML.string("NaN"), slot: .assertOperand) == .number(.nan))
        #expect(try formula(XML.string("1d"), slot: .assertOperand) == .number(1))
        // Java accepts a signed NaN; here a parse failure would be a refusal, not NaN.
        #expect(try formula(XML.string("-NaN"), slot: .assertOperand) == .number(.nan))
        #expect(try formula(XML.number("90"), slot: .assertOperand) == .number(90))
        #expect(try blockers(XML.string("abc"), slot: .assertOperand) == [.stringValue(.assertOperand)])
        // Only the root is the assert's own context; below it, the parent decides.
        let sum = XML.op("PLUS", XML.string("abc"), XML.number("1"))
        #expect(try formula(sum, slot: .assertOperand) == .binary(.plus, .number(.nan), .number(1)))
    }

    /// SetVariable stores a string that `tryParseDouble` rejects as a string
    /// (`SetVariableAction.kt:49-64`); it is only numeric where every later read
    /// agrees, so `fFdD` is refused here too.
    @Test func variableValueParsesStrictlyOrIsRefused() throws {
        #expect(try formula(XML.string("2"), slot: .variableValue) == .number(2))
        #expect(try formula(XML.string("NaN"), slot: .variableValue) == .number(.nan))
        #expect(try blockers(XML.string("abc"), slot: .variableValue) == [.stringValue(.variableValue)])
        #expect(try blockers(XML.string("1d"), slot: .variableValue) == [.stringValue(.variableValue)])
        #expect(try blockers(XML.number("1d"), slot: .variableValue) == [.stringValue(.variableValue)])
    }
}
