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
        // Stub for the US-104 red phase — writes nothing yet.
        _ = (stream, name)
        bytes = []
    }
}
