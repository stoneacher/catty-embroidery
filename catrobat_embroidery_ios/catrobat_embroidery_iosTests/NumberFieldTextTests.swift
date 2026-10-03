@testable import catrobat_embroidery_ios
import EditorCore
import ProgramModel
import Testing

/// US-410: the number field's own spelling of a literal, which must parse back exactly.
@Suite("Number field text")
struct NumberFieldTextTests {
    /// What the number field shows must parse back to the same value: `FormulaText` prints a
    /// U+2212 minus and rounds to six decimals, either of which would make opening the editor
    /// and leaving the field untouched rewrite the brick.
    @Test("the field's text parses back to exactly the stored value", arguments: [
        0, 10, -5, 2.5, -0.25, 1 / 3, 1e-7, 1e20, -1e300, Double.greatestFiniteMagnitude
    ] as [Double])
    func fieldTextRoundTrips(value: Double) {
        for separator in [".", ","] {
            let text = NumberFieldText.text(for: value, decimalSeparator: separator)
            #expect(NumberEntry.parse(text, decimalSeparator: separator) == .success(.number(value)), "\(text)")
        }
    }

    @Test("whole numbers are spelled without a fraction, and the locale's separator is used")
    func fieldTextSpelling() {
        #expect(NumberFieldText.text(for: 10, decimalSeparator: ".") == "10")
        #expect(NumberFieldText.text(for: -5, decimalSeparator: ".") == "-5")
        #expect(NumberFieldText.text(for: 2.5, decimalSeparator: ",") == "2,5")
    }
}
