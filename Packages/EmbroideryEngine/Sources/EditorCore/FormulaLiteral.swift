import ProgramModel

/// The number-pad boundary (US-404, ADR-037): turns what a person typed into a
/// `.number` literal, or says which rule the text broke.
///
/// ADR-025's shape one layer up — reject at the boundary with a reason. The
/// reason this exists at all is that ordinary input reaches `+∞`:
/// `Double("1e400")` and a 310-digit entry are both infinite, and the program
/// document keeps the default `JSONEncoder`, which throws on a non-finite value.
/// Rejecting here is what keeps autosave working after someone leans on the 9
/// key.
///
/// Lives in `EditorCore`, not `ProgramModel`: `ProgramModel`'s API *is* the
/// serialized format (ADR-033), and a parser for user input is not part of the
/// file.
public enum FormulaLiteral {
    /// Parses `text` against the literal grammar, then converts, then checks
    /// finiteness — in that order.
    ///
    /// The grammar is ASCII only:
    /// `-?(digits[.digits*] | .digits)([eE][+-]?digits)?`. It runs *before*
    /// `Double(_:)` because that initializer is wider: it accepts `inf`, `nan`,
    /// hex floats and a leading `+`. So `"nan"` is `.malformed` rather than
    /// `.nonFinite`, and `"0x1p3"` is `.malformed` rather than `8`.
    ///
    /// Underflow is accepted: `"1e-400"` is `.number(0)`. A decimal comma is
    /// malformed — mapping a locale's separator is the editor's job (US-410).
    /// A leading minus is part of the literal (`.number(-5)`), matching how the
    /// templates and samples spell negative values.
    public static func parse(_ text: String) -> Result<Formula, FormulaLiteralError> {
        guard !text.isEmpty else {
            return .failure(.empty)
        }
        guard matchesGrammar(text.utf8), let value = Double(text) else {
            return .failure(.malformed)
        }
        guard value.isFinite else {
            return .failure(.nonFinite)
        }
        return .success(.number(value))
    }

    /// A hand-written scanner rather than a `Regex`: `\d` in a Swift `Regex`
    /// matches Unicode digits, and a stored `Regex` is not `Sendable`.
    private static func matchesGrammar(_ bytes: String.UTF8View) -> Bool {
        var cursor = bytes.startIndex
        func skipDigits() -> Int {
            var count = 0
            while cursor != bytes.endIndex, isDigit(bytes[cursor]) {
                bytes.formIndex(after: &cursor)
                count += 1
            }
            return count
        }
        func consume(_ byte: UInt8) -> Bool {
            guard cursor != bytes.endIndex, bytes[cursor] == byte else { return false }
            bytes.formIndex(after: &cursor)
            return true
        }

        _ = consume(UInt8(ascii: "-"))
        let integerDigits = skipDigits()
        let fractionDigits = consume(UInt8(ascii: ".")) ? skipDigits() : 0
        guard integerDigits + fractionDigits > 0 else {
            return false
        }
        if consume(UInt8(ascii: "e")) || consume(UInt8(ascii: "E")) {
            if !consume(UInt8(ascii: "+")) {
                _ = consume(UInt8(ascii: "-"))
            }
            guard skipDigits() > 0 else {
                return false
            }
        }
        return cursor == bytes.endIndex
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }
}

/// Why typed text is not a number literal. The case is the reason; the editor
/// (US-410) maps each one to localized copy, as ADR-025's `Field` feeds
/// localized nouns — `EditorCore` ships no resources.
public enum FormulaLiteralError: Error, Equatable, Sendable {
    /// Nothing was typed.
    case empty
    /// The text is not a number in the literal grammar: letters, a second
    /// decimal point, whitespace, `inf`/`nan`, a hex float, a decimal comma.
    case malformed
    /// A well-formed number too large for a `Double` — `1e400`, or a long run of
    /// digits — which would round to ±∞ and could not be saved.
    case nonFinite
}
