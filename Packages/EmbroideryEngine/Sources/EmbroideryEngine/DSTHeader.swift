/// The 512-byte Tajima DST file header, derived from `EmbroideryStream`
/// metadata. Byte format per Catroid `DSTFileConstants.DST_HEADER` (each
/// field `\n` + 0x1A terminated, numeric padding NUL, label padding space,
/// space fill to 512); field semantics per ADR-012 — extents relative to
/// the first stitch, magnitudes only, and `CO` counts color blocks.
public struct DSTHeader: Hashable, Sendable {
    /// The 512 header bytes, in file order.
    public let bytes: [UInt8]

    /// Derives all fields from the stream's metadata plus the design name
    /// (sanitized to ASCII, truncated to 15 characters — Catroid's limit,
    /// not Catty's 16).
    public init(stream: EmbroideryStream, name: String) {
        let first = stream.firstStitchPosition ?? EmbroideryPoint(x: 0, y: 0)
        let last = stream.lastStitchPosition ?? first
        let box = stream.boundingBox ?? .init(min: first, max: first)

        var bytes: [UInt8] = []
        Self.appendField(&bytes, "LA", Self.sanitized(name), width: 15, pad: 0x20)
        Self.appendField(&bytes, "ST", "\(stream.count)", width: 6)
        Self.appendField(&bytes, "CO", "\(stream.colorChangeCount + 1)", width: 2)
        Self.appendField(&bytes, "+X", "\(max(box.max.x - first.x, 0))", width: 4)
        Self.appendField(&bytes, "-X", "\(abs(min(box.min.x - first.x, 0)))", width: 4)
        Self.appendField(&bytes, "+Y", "\(max(box.max.y - first.y, 0))", width: 4)
        Self.appendField(&bytes, "-Y", "\(abs(min(box.min.y - first.y, 0)))", width: 4)
        Self.appendField(&bytes, "AX", "\(last.x - first.x)", width: 5)
        Self.appendField(&bytes, "AY", "\(last.y - first.y)", width: 5)
        Self.appendField(&bytes, "MX", "0", width: 5)
        Self.appendField(&bytes, "MY", "0", width: 5)
        Self.appendField(&bytes, "PD", "*****", width: 5)
        bytes += Array(repeating: 0x20, count: 512 - bytes.count)
        self.bytes = bytes
    }

    /// Replaces every non-ASCII scalar with "_" and truncates to Catroid's
    /// 15-character label limit; an empty name stays empty.
    private static func sanitized(_ name: String) -> String {
        String(name.unicodeScalars.map { $0.isASCII ? Character($0) : "_" }.prefix(15))
    }

    /// Appends one `TAG:value` field left-justified to `width` with `pad`,
    /// terminated by `\n` + 0x1A. Field values are bounded by the stage
    /// geometry, so exceeding the Tajima field width is a programmer error.
    private static func appendField(
        _ bytes: inout [UInt8],
        _ tag: String,
        _ value: String,
        width: Int,
        pad: UInt8 = 0x00
    ) {
        let valueBytes = Array(value.utf8)
        precondition(valueBytes.count <= width, "\(tag) value \(value) exceeds field width \(width)")
        bytes += Array("\(tag):".utf8)
        bytes += valueBytes
        bytes += Array(repeating: pad, count: width - valueBytes.count)
        bytes += [0x0A, 0x1A]
    }
}
