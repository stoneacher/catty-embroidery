/// The number field's spelling of a literal (US-410) — **not** `FormulaText`'s.
///
/// The row's text is for reading: a U+2212 minus and at most six decimals. The field's text is
/// for editing, and has to parse back to exactly the stored value, or opening the editor and
/// leaving the field alone would rewrite the brick. So: an ASCII hyphen-minus, Swift's shortest
/// round-tripping spelling, and the locale's decimal separator, which `NumberEntry` maps back.
nonisolated enum NumberFieldText {
    static func text(for value: Double, decimalSeparator: String) -> String {
        // Whole numbers below 2^53 are exact in `Int64` and spelled without "\.0".
        // Not negative zero: `Int64(-0.0)` is `0`, which would lose the sign (Codex round 2);
        // `"\(-0.0)"` is `"-0.0"`, which parses back to it.
        if value == value.rounded(), abs(value) < 9_007_199_254_740_992, value.sign == .plus || value != 0 {
            return String(Int64(value))
        }
        let spelled = "\(value)"
        return decimalSeparator == "." ? spelled : spelled.replacing(".", with: decimalSeparator)
    }
}
