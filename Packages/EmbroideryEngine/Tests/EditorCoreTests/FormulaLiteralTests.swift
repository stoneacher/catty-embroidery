import EditorCore
import ProgramModel
import Testing

/// US-404 test plan 6–8: the number-pad boundary. ADR-025's shape one layer up —
/// reject at the boundary and say which rule was broken — so a value the
/// document cannot encode never enters the model through ordinary input.
///
/// The accepted grammar is ASCII `-?(digits[.digits*] | .digits)([eE][+-]?digits)?`
/// and nothing else. `Double(String)` alone is wider — it takes `inf`, `nan`,
/// hex floats and a leading `+` (executed at planning) — which is why several
/// cases below exist to prove the grammar runs *before* the conversion.
@Suite("Formula literal")
struct FormulaLiteralTests {
    // MARK: 6 — non-finite

    @Test("test plan 6: 1e400 is a non-finite failure, not a success carrying +∞", arguments: ["1e400", "-1e400"])
    func overflowingExponentIsNonFinite(_ text: String) {
        let result = FormulaLiteral.parse(text)
        #expect(result == .failure(.nonFinite))
        #expect((try? result.get()) == nil, "\(text) must not parse to a value")
    }

    /// The threshold is decimal→binary rounding, executed rather than derived
    /// (ADR-019's screening question: yes, this sits on a threshold). The first
    /// spelling rounds to `greatestFiniteMagnitude`; the second rounds past it.
    @Test("test plan 6: the largest finite spelling succeeds and its neighbour fails")
    func finiteBoundary() {
        #expect(FormulaLiteral.parse("1.7976931348623157e308") == .success(.number(.greatestFiniteMagnitude)))
        #expect(FormulaLiteral.parse("1.7976931348623159e308") == .failure(.nonFinite))
    }

    // MARK: 7 — the realistic route

    /// Separate from test 6 because this is how a person actually gets there:
    /// no exponent, just a finger left on the 9 key.
    @Test("test plan 7: a 310-digit entry is the same non-finite failure")
    func longDigitRunIsNonFinite() {
        #expect(FormulaLiteral.parse(String(repeating: "9", count: 310)) == .failure(.nonFinite))
    }

    @Test("test plan 7: a 309-digit entry that stays finite succeeds")
    func longFiniteDigitRunSucceeds() {
        let text = "1" + String(repeating: "0", count: 308)
        #expect(FormulaLiteral.parse(text) == .success(.number(1e308)))
    }

    // MARK: 8 — ordinary input

    static let accepted: [(text: String, value: Double)] = [
        ("0", 0), ("42", 42), ("-5", -5), ("3.25", 3.25), ("-0.5", -0.5),
        (".5", 0.5), ("1.", 1), ("1e5", 100_000), ("2.5E-3", 0.0025), ("1e+2", 100),
        ("00012", 12),
        // Underflow is silent and finite, and accepted: the document can hold
        // zero, and refusing a tiny number as "too large" would be a lie.
        ("1e-400", 0)
    ]

    /// Exact case equality: a leading minus is `.number(-5)`, not
    /// `.unaryMinus(.number(5))` — the templates and the samples spell it that
    /// way, and a parser that disagreed would make round trips through the
    /// editor change a program nobody edited.
    @Test("test plan 8: ordinary numbers parse to a literal", arguments: accepted.map(\.text))
    func ordinaryInputParses(_ text: String) throws {
        let expected = try #require(Self.accepted.first { $0.text == text }).value
        #expect(FormulaLiteral.parse(text) == .success(.number(expected)))
    }

    /// Pinned at review: typed `-0` is a negative zero, as `Double("-0")` gives
    /// it — the literal is what was typed, and the document keeps the sign
    /// (`negativeZeroKeepsItsSign`). Exact equality cannot see the sign, so it is
    /// asserted on its own.
    @Test("test plan 8: -0 parses to a negative zero")
    func negativeZeroIsNegative() throws {
        guard case let .number(value) = try FormulaLiteral.parse("-0").get() else {
            Issue.record("-0 did not parse to a number literal")
            return
        }
        #expect(value == 0)
        #expect(value.sign == .minus)
    }

    @Test("test plan 8: empty input is its own reason")
    func emptyIsEmpty() {
        #expect(FormulaLiteral.parse("") == .failure(.empty))
    }

    /// `inf`/`nan` must be *malformed*, not *non-finite*, and `0x1p3` must not be
    /// `.success(8)`: those are what show the grammar runs before `Double(_:)`.
    /// **Only `+1`, the inf/nan family and hex floats get past `Double(_:)`**;
    /// every other entry here it already rejects, so those pin the outcome, not
    /// the scanner (`swift-code-reviewer` probed each). The Unicode digits and
    /// U+2212 are there because `\d` in a Swift `Regex` matches them.
    @Test("test plan 8: anything outside the grammar is malformed", arguments: [
        "abc", "1.2.3", "-", ".", "+1", " 1", "1 ", "1,5", "1_000", "--1", "1e", "e5", "1e5.5",
        "inf", "-inf", "Infinity", "infinity", "nan", "NaN", "-nan", "snan", "nan(0x1)",
        "0x1p3", "0X1P3", "0x10",
        "٣", "１", "\u{2212}1"
    ])
    func outsideTheGrammarIsMalformed(_ text: String) {
        #expect(FormulaLiteral.parse(text) == .failure(.malformed))
    }
}
