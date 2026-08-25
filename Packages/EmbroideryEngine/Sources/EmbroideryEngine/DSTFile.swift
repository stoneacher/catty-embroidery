import Foundation

/// A complete Tajima DST file serialized from an `EmbroideryStream` —
/// the engine's primary export entry point (US-106).
///
/// Layout: the 512-byte `DSTHeader`, one 3-byte `DSTStitchRecord` per
/// stitch, and the `00 00 F3` end-of-file record. The first stitch encodes
/// as a zero-delta record carrying its own flags; every later record is
/// the delta between consecutive absolute positions, kept encodable by
/// long-move interpolation (US-105). At an exact ±121-unit boundary the
/// interpolation guard's difference rounding and this delta's position
/// rounding can disagree by one unit; the stream now decides on both, so
/// the move splits instead of encoding an out-of-range delta (ADR-020,
/// closing the ADR-012 follow-up this comment used to track — Catroid
/// silently emits a corrupt record there). Byte semantics are pinned by
/// ADR-012 and ADR-013.
public struct DSTFile: Hashable, Sendable {
    /// The complete file bytes. Primary API — compare or persist directly;
    /// building it does no I/O.
    public let data: Data

    /// Serializes `stream` under the given design name (sanitized and
    /// truncated to 15 characters by `DSTHeader`).
    ///
    /// - Throws: `DSTSerializationError.fieldOverflow` when the design is
    ///   larger than a header field can describe (US-211, ADR-025). Only the
    ///   header can fail: the record loop's deltas are kept encodable by the
    ///   stream itself (ADR-020).
    public init(stream: EmbroideryStream, name: String) throws {
        var bytes = try DSTHeader(stream: stream, name: name).bytes
        bytes.reserveCapacity(512 + 3 * stream.count + 3)

        var previous: EmbroideryPoint?
        for stitch in stream.stitches {
            bytes += DSTStitchRecord(
                from: previous ?? stitch.position,
                to: stitch.position,
                isJump: stitch.isJump,
                isColorChange: stitch.isColorChange
            ).bytes
            previous = stitch.position
        }

        bytes += Self.endOfFileRecord
        data = Data(bytes)
    }

    /// Convenience wrapper around `Data.write(to:options:)`; `data` is the
    /// primary, I/O-free API. Writes atomically so an interrupted export
    /// never leaves a truncated file.
    public func write(to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    /// The 3-byte end-of-file record every DST file closes with
    /// (Catroid `DSTFileConstants.FILE_END`).
    private static let endOfFileRecord: [UInt8] = [0x00, 0x00, 0xF3]
}
