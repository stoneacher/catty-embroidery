import ProgramModel

/// The number field's text, mapped for the locale and parsed (US-410).
public enum NumberEntry {
    public static func parse(_: String, decimalSeparator _: String) -> Result<Formula, FormulaLiteralError> {
        .failure(.empty)
    }
}
