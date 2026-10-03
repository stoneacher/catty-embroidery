/// The rules a variable name must satisfy (US-410).
///
/// `Variable.swift` says name uniqueness "is enforced by the editor"; M4 is the
/// first editor, and these are the other rules it enforces. They answer the
/// question US-407 handed on — names that imitate the display syntax — by
/// **restricting the characters** (decided by Sebastian, 2026-10-03):
///
/// - **No quotation mark anywhere.** `formula.variable` wraps a name in
///   quotation marks, so a name containing one could render as a sum
///   (`"a" + "b"`). Unicode's `Quotation_Mark` property is used rather than
///   ASCII `"` alone, which covers whatever delimiters a translator picks.
///   Escaping was rejected: it depends on the locale's delimiters, and it does
///   not help with the placeholder collision.
/// - **No opening punctuation at the start.** The `(no variable)` placeholder
///   begins with one, so no name can be spelled like it. Only the start is
///   constrained; `x(1)` is fine. `AppStringsTests` pins that every locale's
///   placeholder does begin with opening punctuation.
/// - Not empty, no surrounding whitespace, no control characters.
///
/// The check is **exact** — it does not trim — so the funnel accepts a name
/// only as given. Trimming what someone typed is the text field's job.
public enum VariableName {
    public static func validate(_ name: String) -> Result<String, VariableNameProblem> {
        let scalars = name.unicodeScalars
        guard scalars.contains(where: { !$0.properties.isWhitespace }) else {
            return .failure(.empty)
        }
        // Non-empty after the guard above.
        if scalars.first!.properties.isWhitespace || scalars.last!.properties.isWhitespace {
            return .failure(.surroundingWhitespace)
        }
        if scalars.contains(where: { $0.properties.generalCategory == .control }) {
            return .failure(.controlCharacter)
        }
        if scalars.contains(where: \.properties.isQuotationMark) {
            return .failure(.quotationMark)
        }
        if scalars.first!.properties.generalCategory == .openPunctuation {
            return .failure(.leadingOpenPunctuation)
        }
        return .success(name)
    }
}

/// Which rule a variable name broke, in the order they are checked. The editor
/// maps each to localized copy; `EditorCore` ships no resources.
public enum VariableNameProblem: Error, Sendable, Equatable {
    /// Empty, or whitespace only.
    case empty
    /// Leading or trailing whitespace.
    case surroundingWhitespace
    /// A control character, such as a newline inside the name.
    case controlCharacter
    /// A quotation mark of any script — the display delimiter.
    case quotationMark
    /// Opening punctuation first — the placeholder's spelling.
    case leadingOpenPunctuation
}
