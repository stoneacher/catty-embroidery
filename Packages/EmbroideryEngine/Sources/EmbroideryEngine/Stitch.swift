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
    /// swallowed parse exception (ADR-015). Each of the six digits must be
    /// 0-9/a-f/A-F: Java's `Integer.decode` rejects signs and spaces inside
    /// the pairs, unlike Swift's lenient `UInt8(_:radix:)`, so validation is
    /// per code unit; surrogate halves and non-ASCII units in the pair
    /// region never match, exactly as they throw in Java.
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

    private static func hexDigit(_ unit: UInt16) -> UInt8? {
        switch unit {
        case UInt16(UInt8(ascii: "0")) ... UInt16(UInt8(ascii: "9")):
            UInt8(unit) - UInt8(ascii: "0")
        case UInt16(UInt8(ascii: "a")) ... UInt16(UInt8(ascii: "f")):
            UInt8(unit) - UInt8(ascii: "a") + 10
        case UInt16(UInt8(ascii: "A")) ... UInt16(UInt8(ascii: "F")):
            UInt8(unit) - UInt8(ascii: "A") + 10
        default:
            nil
        }
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
