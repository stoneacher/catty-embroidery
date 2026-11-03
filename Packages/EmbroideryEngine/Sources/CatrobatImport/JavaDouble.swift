/// Java's `Double.valueOf(String)` / `Double.parseDouble`, which Catroid uses to
/// read every formula literal (brief D4): `nil` exactly where Java throws
/// `NumberFormatException`.
///
/// The grammar is `java.lang.Double.valueOf`'s: surrounding characters ≤ U+0020
/// are trimmed; then an optional sign and `NaN`, `Infinity`, a decimal with an
/// optional exponent, or a hexadecimal with a mandatory binary exponent; each
/// number may end in one of `fFdD`, which changes nothing (the result is still a
/// `double`). Digits are ASCII only. The value itself is computed by Swift's
/// correctly rounded parser on the validated text, so it agrees with Java's.
enum JavaDouble {
    static func parse(_ text: String) -> Double? {
        var scalars = Substring(text).unicodeScalars[...]
        while let first = scalars.first, first.value <= 0x20 {
            scalars.removeFirst()
        }
        while let last = scalars.last, last.value <= 0x20 {
            scalars.removeLast()
        }
        var body = String(String.UnicodeScalarView(scalars))[...]

        var negative = false
        if let sign = body.first, sign == "+" || sign == "-" {
            negative = sign == "-"
            body = body.dropFirst()
        }
        if body == "NaN" {
            return .nan
        }
        if body == "Infinity" {
            return negative ? -.infinity : .infinity
        }

        if let suffix = body.last, "fFdD".contains(suffix) {
            body = body.dropLast()
        }
        let valid = body.hasPrefix("0x") || body.hasPrefix("0X")
            ? isHexadecimal(body.dropFirst(2))
            : isDecimal(body)
        guard valid, let magnitude = Double(String(body)) else { return nil }
        return negative ? -magnitude : magnitude
    }

    /// Catroid's `tryParseDouble` for function arguments (`Conversions.kt:35-44`):
    /// any `f`, `F`, `d` or `D` anywhere, so `Infinity` and hex digits too, is null.
    static func parseArgument(_ text: String) -> Double? {
        text.contains { "fFdD".contains($0) } ? nil : parse(text)
    }

    /// `digits ['.' digits] | '.' digits`, then `[eE][+-]digits`.
    private static func isDecimal(_ text: Substring) -> Bool {
        var rest = text
        let (integer, afterInteger) = digits(rest, hex: false)
        rest = afterInteger
        var fraction = Substring()
        if rest.first == "." {
            (fraction, rest) = digits(rest.dropFirst(), hex: false)
        }
        // Swift's parser also rejects every digitless form (checked 2026-11-03),
        // so no test can fail without this guard; it is kept so Java's grammar does
        // not depend on that.
        guard !integer.isEmpty || !fraction.isEmpty else { return false }
        if let marker = rest.first, marker == "e" || marker == "E" {
            return isSignedExponent(rest.dropFirst())
        }
        return rest.isEmpty
    }

    /// After `0x`: `hexdigits ['.' hexdigits] | '.' hexdigits`, then a mandatory
    /// `[pP][+-]digits`.
    private static func isHexadecimal(_ text: Substring) -> Bool {
        var rest = text
        let (integer, afterInteger) = digits(rest, hex: true)
        rest = afterInteger
        var fraction = Substring()
        if rest.first == "." {
            (fraction, rest) = digits(rest.dropFirst(), hex: true)
        }
        guard !integer.isEmpty || !fraction.isEmpty,
              let marker = rest.first, marker == "p" || marker == "P"
        else { return false }
        return isSignedExponent(rest.dropFirst())
    }

    private static func isSignedExponent(_ text: Substring) -> Bool {
        var rest = text
        if let sign = rest.first, sign == "+" || sign == "-" {
            rest = rest.dropFirst()
        }
        let (exponent, after) = digits(rest, hex: false)
        return !exponent.isEmpty && after.isEmpty
    }

    private static func digits(_ text: Substring, hex: Bool) -> (Substring, Substring) {
        let end = text.firstIndex { character in
            guard character.isASCII else { return true }
            return hex ? !character.isHexDigit : !("0" ... "9").contains(character)
        } ?? text.endIndex
        return (text[..<end], text[end...])
    }
}
