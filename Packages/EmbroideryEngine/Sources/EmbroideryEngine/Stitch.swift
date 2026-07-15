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

    /// Stub for the US-110 red phase — parsing lands with the green phase.
    public init?(hexString _: String) {
        nil
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
