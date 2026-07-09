import Foundation

/// A complete Tajima DST file serialized from an `EmbroideryStream`
/// (US-106). Stub for the TDD red baseline — assembly of header, records,
/// and the end-of-file record follows.
public struct DSTFile: Hashable, Sendable {
    /// The complete file bytes.
    public let data: Data

    public init(stream: EmbroideryStream, name: String) {
        _ = stream
        _ = name
        data = Data()
    }

    /// Writes `data` to `url`.
    public func write(to url: URL) throws {
        try data.write(to: url)
    }
}
