/// One 3-byte Tajima DST stitch record: a relative needle movement of up to
/// ±121 embroidery units per axis, plus jump / color-change flags.
public struct DSTStitchRecord: Hashable, Sendable {
    /// Largest encodable delta magnitude per axis, in embroidery units
    /// (Catroid `MAX_DISTANCE`). The bound is inclusive: ±121 is legal.
    public static let maxDelta = 121

    /// Delta → ternary bit pattern lookup (indices 0…121 = +0…+121,
    /// 122…242 = −1…−121). Stub for the US-103 red phase.
    static let conversionTable: [UInt16] = []

    /// The three record bytes, in file order.
    public let bytes: [UInt8]

    /// Encodes a delta in embroidery units. Both `dx` and `dy` must be
    /// within `-maxDelta...maxDelta`; US-105's interpolation keeps stream
    /// deltas inside that range, so violations are programmer errors.
    public init(dx: Int, dy: Int, isJump: Bool = false, isColorChange: Bool = false) {
        // Stub for the US-103 red phase — encodes nothing yet.
        _ = (dx, dy, isJump, isColorChange)
        bytes = [0, 0, 0]
    }

    /// Encodes the movement between two absolute positions. Positions are
    /// already-rounded embroidery units, so the delta is round-then-subtract
    /// by construction (ADR-012: never convert the difference).
    public init(
        from previous: EmbroideryPoint,
        to current: EmbroideryPoint,
        isJump: Bool = false,
        isColorChange: Bool = false
    ) {
        self.init(
            dx: current.x - previous.x,
            dy: current.y - previous.y,
            isJump: isJump,
            isColorChange: isColorChange
        )
    }
}
