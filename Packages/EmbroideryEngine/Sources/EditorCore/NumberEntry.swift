import ProgramModel

/// The number field's text, mapped for the locale and handed to
/// `FormulaLiteral.parse` (US-410).
///
/// ADR-037 left the decimal separator to this story and kept the literal
/// grammar ASCII. So the mapping is one step, in front of the grammar: the
/// locale's separator becomes `.`. The ASCII point is accepted in every locale
/// too, because a hardware keyboard or a paste can produce it, and it is never
/// ambiguous. Nothing else is guessed — `1,5` in a point locale is malformed,
/// not 1.5, since it is more likely a grouping slip than a decimal.
///
/// Here rather than in the app so the rule runs on the fast `swift test` gate.
public enum NumberEntry {
    public static func parse(_ text: String, decimalSeparator: String) -> Result<Formula, FormulaLiteralError> {
        var mapped = text.trimmingWhitespace
        if decimalSeparator != ".", !decimalSeparator.isEmpty {
            mapped = mapped.replacing(decimalSeparator, with: ".")
        }
        return FormulaLiteral.parse(mapped)
    }
}

private extension String {
    /// Foundation-free trim, so `EditorCore` stays as light as ADR-033 has it.
    var trimmingWhitespace: String {
        let scalars = unicodeScalars
        guard let start = scalars.firstIndex(where: { !$0.properties.isWhitespace }) else { return "" }
        // Non-nil: `start` itself is a non-whitespace scalar.
        let end = scalars.lastIndex { !$0.properties.isWhitespace } ?? start
        return String(scalars[start ... end])
    }
}
