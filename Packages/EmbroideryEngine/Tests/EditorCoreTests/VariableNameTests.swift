import EditorCore
import Testing

/// US-410's answer to the question US-407 handed on: names that imitate the
/// display syntax. **Restrict the characters** (decided by Sebastian,
/// 2026-10-03).
///
/// - A quotation mark anywhere would let `.variable("a\" + \"b")` render as a
///   sum, so any scalar Unicode calls a quotation mark is refused. That covers
///   every locale's choice of delimiter for `formula.variable`, not only ASCII.
/// - A name may not *begin* with opening punctuation, so it can never be
///   spelled like the `(no variable)` placeholder. The app pins that every
///   locale's placeholder does begin with one (`AppStringsTests`).
///
/// The funnel validates exactly — it does not trim — so `validate(name)`
/// succeeds only with the name it was given. Trimming is the field's job.
@Suite("Variable names")
struct VariableNameTests {
    @Test("ordinary names are accepted unchanged", arguments: ["Side", "Inner Loop", "x2", "Länge", "長さ", "a-b_c"])
    func accepted(name: String) {
        #expect(VariableName.validate(name) == .success(name))
    }

    @Test("an empty or blank name is refused", arguments: ["", " ", "\t"])
    func empty(name: String) {
        #expect(VariableName.validate(name) == .failure(.empty))
    }

    @Test("surrounding whitespace is refused rather than trimmed", arguments: [" Side", "Side ", "Side\n"])
    func surroundingWhitespace(name: String) {
        #expect(VariableName.validate(name) == .failure(.surroundingWhitespace))
    }

    @Test("a control character is refused", arguments: ["Si\u{0}de", "Si\u{7}de", "a\nb"])
    func controlCharacter(name: String) {
        #expect(VariableName.validate(name) == .failure(.controlCharacter))
    }

    /// The US-407 case itself, then a sample of other locales' delimiters:
    /// German „…“, French «…», Japanese 「…」, and the apostrophe, which
    /// Unicode also counts as a quotation mark.
    @Test("any quotation mark is refused",
          arguments: ["a\" + \"b", "„Seite“", "«côté»", "it's", "a\u{2019}b", "\u{201C}x\u{201D}", "x「y」"])
    func quotationMark(name: String) {
        #expect(VariableName.validate(name) == .failure(.quotationMark))
    }

    @Test("a name may not start with opening punctuation",
          arguments: ["(no variable)", "(empty)", "[x]", "{x}", "（x）"])
    func leadingOpenPunctuation(name: String) {
        #expect(VariableName.validate(name) == .failure(.leadingOpenPunctuation))
    }

    /// Only the *start* is constrained: a bracket inside a name cannot pass for
    /// the placeholder, and refusing it would be hostile for nothing.
    @Test("brackets later in the name are fine", arguments: ["x(1)", "Loop [outer]"])
    func innerBrackets(name: String) {
        #expect(VariableName.validate(name) == .success(name))
    }
}
