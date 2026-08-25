/// The 512-byte Tajima DST file header, derived from `EmbroideryStream`
/// metadata. Byte format per Catroid `DSTFileConstants.DST_HEADER` (each
/// field `\n` + 0x1A terminated, numeric padding NUL, label padding space,
/// space fill to 512); field semantics per ADR-012 — extents relative to
/// the first stitch, magnitudes only, and `CO` counts color blocks.
///
/// Initialization throws `DSTSerializationError` when a value does not fit its
/// fixed-width field (US-211, ADR-025). Three fields are reachable from
/// ordinary input — the 4-wide extents, the 2-wide `CO`, the 6-wide `ST` — and
/// the reachability is asymmetric: inside ADR-007's 500x500 stage the maximum
/// per-direction extent is 1000 units, whereas `CO` and `ST` overflow without
/// leaving the stage. `LA`, `AX` and `AY` cannot overflow; ADR-025 records why,
/// and why field *emission order* is contractual rather than cosmetic.
public struct DSTHeader: Hashable, Sendable {
    /// The 512 header bytes, in file order.
    public let bytes: [UInt8]

    /// Derives all fields from the stream's metadata plus the design name
    /// (sanitized to ASCII, truncated to 15 characters — Catroid's limit,
    /// not Catty's 16).
    ///
    /// - Throws: `DSTSerializationError.fieldOverflow` for the first field, in
    ///   emission order, whose value exceeds its width.
    public init(stream: EmbroideryStream, name: String) throws {
        let first = stream.firstStitchPosition ?? EmbroideryPoint(x: 0, y: 0)
        let last = stream.lastStitchPosition ?? first
        let box = stream.boundingBox ?? .init(min: first, max: first)

        // Emission order is a contract, not the byte layout's accident
        // (ADR-025). `ST` precedes the extents, so a throwing `ST` check bounds
        // `stream.count` at 999,999 before the subtractions below run — which,
        // with ADR-020's <=121-unit-per-axis delta, bounds every span at
        // ~1.21e8 and is what keeps this `Int` arithmetic unreachable at
        // overflow magnitudes. The extents precede `AX`/`AY` for the same kind
        // of reason: a 4-digit extent bounds `AX` at "-9999", exactly filling
        // its 5-wide field. Reordering either pair breaks a guarantee.
        var bytes: [UInt8] = []
        try Self.appendField(&bytes, .label, Self.sanitized(name))
        try Self.appendField(&bytes, .stitchCount, "\(stream.count)")
        try Self.appendField(&bytes, .colorBlocks, "\(stream.colorChangeCount + 1)")
        try Self.appendField(&bytes, .extentPlusX, "\(max(box.max.x - first.x, 0))")
        try Self.appendField(&bytes, .extentMinusX, "\(abs(min(box.min.x - first.x, 0)))")
        try Self.appendField(&bytes, .extentPlusY, "\(max(box.max.y - first.y, 0))")
        try Self.appendField(&bytes, .extentMinusY, "\(abs(min(box.min.y - first.y, 0)))")
        try Self.appendField(&bytes, .axisX, "\(last.x - first.x)")
        try Self.appendField(&bytes, .axisY, "\(last.y - first.y)")
        try Self.appendField(&bytes, .maxX, "0")
        try Self.appendField(&bytes, .maxY, "0")
        try Self.appendField(&bytes, .previousDesign, "*****")
        bytes += Array(repeating: 0x20, count: 512 - bytes.count)
        self.bytes = bytes
    }

    /// Replaces every non-ASCII scalar with "_" and truncates to Catroid's
    /// 15-character label limit; an empty name stays empty.
    ///
    /// The order matters: mapping over `unicodeScalars` *before* `prefix(15)`
    /// is what makes `LA` unable to overflow, since every surviving `Character`
    /// is then a single ASCII scalar and 15 characters are 15 bytes. Moving the
    /// `prefix` ahead of the `map` would make it a live trap, because
    /// `appendField` counts UTF-8 bytes where `prefix` counts characters.
    private static func sanitized(_ name: String) -> String {
        String(name.unicodeScalars.map { $0.isASCII ? Character($0) : "_" }.prefix(15))
    }

    /// Appends one `TAG:value` field left-justified to the field's fixed width
    /// with its pad byte, terminated by `\n` + 0x1A.
    ///
    /// - Throws: `DSTSerializationError.fieldOverflow` if the value's UTF-8
    ///   length exceeds the width. This replaces a `precondition` (US-211):
    ///   the values come from user-authored designs, not from programmer
    ///   error. Nothing is left as a backstop the way `DSTStitchRecord`'s
    ///   precondition was under ADR-020, because that initializer is `public`
    ///   and can be reached directly, whereas this method is `private` with a
    ///   single caller — a retained precondition would guard nothing.
    private static func appendField(
        _ bytes: inout [UInt8],
        _ field: Field,
        _ value: String
    ) throws {
        let valueBytes = Array(value.utf8)
        guard valueBytes.count <= field.width else {
            throw DSTSerializationError.fieldOverflow(
                field: field,
                value: value,
                limit: field.limit
            )
        }
        bytes += Array("\(field.rawValue):".utf8)
        bytes += valueBytes
        bytes += Array(repeating: field.pad, count: field.width - valueBytes.count)
        bytes += [0x0A, 0x1A]
    }
}

public extension DSTHeader {
    /// The header's fixed-width fields, in emission order (Catroid
    /// `DSTFileConstants.DST_HEADER`). The order is contractual — see
    /// `DSTHeader.init` and ADR-025 — and `CaseIterable` follows it, so a
    /// caller can render the fields as the file lays them out.
    enum Field: String, CaseIterable, Sendable {
        case label = "LA"
        case stitchCount = "ST"
        case colorBlocks = "CO"
        case extentPlusX = "+X"
        case extentMinusX = "-X"
        case extentPlusY = "+Y"
        case extentMinusY = "-Y"
        case axisX = "AX"
        case axisY = "AY"
        case maxX = "MX"
        case maxY = "MY"
        case previousDesign = "PD"

        /// The field's fixed byte width.
        public var width: Int {
            switch self {
            case .label: 15
            case .stitchCount: 6
            case .colorBlocks: 2
            case .extentPlusX, .extentMinusX, .extentPlusY, .extentMinusY: 4
            case .axisX, .axisY, .maxX, .maxY, .previousDesign: 5
            }
        }

        /// The largest value the field can express as a non-negative decimal.
        ///
        /// Exact for every field `DSTSerializationError` is reachable from —
        /// `stitchCount`, `colorBlocks` and the four extents, all non-negative
        /// counts. It is *not* the bound on the signed `axisX`/`axisY` (which
        /// reach only -9999 on the negative side) nor a character count for
        /// `label`; those three cannot overflow, per ADR-025.
        public var limit: Int {
            (0 ..< width).reduce(1) { product, _ in product * 10 } - 1
        }

        /// Numeric fields pad with NUL, the label with space (ADR-012).
        var pad: UInt8 { self == .label ? 0x20 : 0x00 }
    }
}
