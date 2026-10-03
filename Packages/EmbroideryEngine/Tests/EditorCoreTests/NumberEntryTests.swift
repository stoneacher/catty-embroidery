import EditorCore
import ProgramModel
import Testing

/// US-410 test-first item 3, the package half: what the number field hands to
/// `FormulaLiteral.parse`. ADR-037 gave the locale's decimal separator to this
/// story; the literal grammar itself stays ASCII and is US-404's.
@Suite("Number entry")
struct NumberEntryTests {
    @Test("item 3: 1e400 and a 310-digit entry are rejected as non-finite, not committed as +∞",
          arguments: ["1e400", String(repeating: "9", count: 310)])
    func nonFiniteIsRejected(text: String) {
        #expect(NumberEntry.parse(text, decimalSeparator: ".") == .failure(.nonFinite))
        #expect(NumberEntry.parse(text, decimalSeparator: ",") == .failure(.nonFinite))
    }

    @Test("the locale's separator is accepted, and so is the ASCII point")
    func bothSeparators() {
        #expect(NumberEntry.parse("2,5", decimalSeparator: ",") == .success(.number(2.5)))
        #expect(NumberEntry.parse("2.5", decimalSeparator: ",") == .success(.number(2.5)))
        #expect(NumberEntry.parse("-0,25", decimalSeparator: ",") == .success(.number(-0.25)))
        #expect(NumberEntry.parse("2.5", decimalSeparator: ".") == .success(.number(2.5)))
    }

    /// A comma is a decimal separator only where the locale says so. In an
    /// English locale "1,5" is most likely a grouping slip, and guessing 1.5
    /// would commit a value the user did not type.
    @Test("a comma outside a comma locale is malformed, not guessed")
    func commaElsewhereIsMalformed() {
        #expect(NumberEntry.parse("1,5", decimalSeparator: ".") == .failure(.malformed))
    }

    /// Two separators are two decimal points once mapped, which the grammar
    /// already refuses — so mixing them cannot smuggle a grouping separator in.
    @Test("a mix of both separators is malformed")
    func mixedSeparators() {
        #expect(NumberEntry.parse("1.000,5", decimalSeparator: ",") == .failure(.malformed))
    }

    /// The field is typed into, so a trailing space from autocomplete or paste
    /// is not the user's intent. Inner whitespace still is not a number.
    @Test("surrounding whitespace is ignored, inner whitespace is not")
    func whitespace() {
        #expect(NumberEntry.parse("  42 ", decimalSeparator: ".") == .success(.number(42)))
        #expect(NumberEntry.parse("4 2", decimalSeparator: ".") == .failure(.malformed))
        #expect(NumberEntry.parse("   ", decimalSeparator: ".") == .failure(.empty))
    }
}
