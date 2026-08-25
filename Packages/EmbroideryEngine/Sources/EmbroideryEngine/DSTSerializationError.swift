/// A design the Tajima header cannot describe (US-211, ADR-025).
///
/// Every field in `DSTHeader` is fixed-width, so a value that does not fit is
/// not a programmer error: extents, colour blocks and stitch counts all come
/// from ordinary user input. US-210 closed the *coordinate* chokepoint with
/// guarded no-ops (ADR-020), but a header field cannot be a no-op — the field
/// is the one place a machine reads to size the design, so clamping it would
/// emit a header that misdescribes the design, undetectably. This is therefore
/// an error a caller handles, and it is throwing rather than failable because
/// the export path must be able to say *which* limit was hit ("118 colour
/// blocks; DST allows 99") — something `Optional` cannot carry.
public enum DSTSerializationError: Error, Equatable, Sendable {
    /// `value` needs more bytes than `field` has. `limit` is the largest value
    /// the field can express.
    ///
    /// Only the first violation in emission order is reported, which is
    /// deterministic and is what keeps `DSTHeader`'s extent arithmetic inside
    /// `Int` (ADR-025): a design busting both `ST` and `+X` is told about `ST`.
    case fieldOverflow(field: DSTHeader.Field, value: String, limit: Int)
}
