/// An RGB thread color. Platform-independent stand-in for UIColor/libGDX
/// Color; hex parsing arrives with the Set Thread Color brick (US-110).
public struct ThreadColor: Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Default thread color, matching both references.
    public static let black = ThreadColor(red: 0, green: 0, blue: 0)

    /// Port of Catroid `SetThreadColorAction` hex parsing (US-110, ADR-012):
    /// the UTF-16 code units at offsets [1,3), [3,5), [5,7) are the RR/GG/BB
    /// hex pairs — UTF-16 because Java `String.substring` counts code units,
    /// so a non-ASCII single-unit character at index 0 still parses (review
    /// find, ADR-015). Unit 0 is skipped without validation (Android
    /// substrings from index 1 regardless of prefix) and everything past
    /// offset 7 is ignored — alpha is discarded. Any malformed input returns
    /// nil so the caller keeps the current color, matching Android's
    /// swallowed parse exception (ADR-015). Java's `Integer.decode` rejects
    /// signs and spaces inside the pairs, unlike Swift's lenient
    /// `UInt8(_:radix:)`, so each of the six digits is validated per code
    /// unit through a port of `Character.digit(char, 16)` — see `hexDigit`.
    public init?(hexString: String) {
        let units = Array(hexString.utf16.prefix(7))
        guard units.count == 7,
              let red = Self.hexPair(high: units[1], low: units[2]),
              let green = Self.hexPair(high: units[3], low: units[4]),
              let blue = Self.hexPair(high: units[5], low: units[6])
        else {
            return nil
        }
        self.init(red: red, green: green, blue: blue)
    }

    private static func hexPair(high: UInt16, low: UInt16) -> UInt8? {
        guard let high = hexDigit(high), let low = hexDigit(low) else { return nil }
        return high << 4 | low
    }

    /// Java `Character.digit(char, 16)` for one UTF-16 code unit: Latin
    /// letters (ASCII and fullwidth) map to 10…35, any Unicode decimal
    /// digit (Nd) to its value, everything else — including lone
    /// surrogates — to nil; values ≥ 16 are not hex digits.
    private static func hexDigit(_ unit: UInt16) -> UInt8? {
        guard let scalar = Unicode.Scalar(unit) else { return nil }
        let value: Int
        switch scalar {
        case "a" ... "z":
            value = Int(unit) - Int(UInt8(ascii: "a")) + 10
        case "A" ... "Z":
            value = Int(unit) - Int(UInt8(ascii: "A")) + 10
        case "\u{FF41}" ... "\u{FF5A}": // fullwidth a…z
            value = Int(unit) - 0xFF41 + 10
        case "\u{FF21}" ... "\u{FF3A}": // fullwidth A…Z
            value = Int(unit) - 0xFF21 + 10
        default:
            let properties = scalar.properties
            guard properties.numericType == .decimal,
                  let numericValue = properties.numericValue
            else {
                return nil
            }
            value = Int(numericValue)
        }
        guard value < 16 else { return nil }
        return UInt8(value)
    }
}

/// One needle penetration in embroidery coordinates, with the DST record
/// flags it will carry (jump, color change).
public struct Stitch: Hashable, Sendable {
    public var position: EmbroideryPoint
    public var color: ThreadColor
    public var isJump: Bool
    public var isColorChange: Bool

    public init(
        position: EmbroideryPoint,
        color: ThreadColor = .black,
        isJump: Bool = false,
        isColorChange: Bool = false
    ) {
        self.position = position
        self.color = color
        self.isJump = isJump
        self.isColorChange = isColorChange
    }
}
