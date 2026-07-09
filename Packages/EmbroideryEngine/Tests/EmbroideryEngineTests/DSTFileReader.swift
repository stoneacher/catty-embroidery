import EmbroideryEngine
import Foundation
import Testing

/// Test-only minimal DST reader (US-106): header fields plus record
/// decoding via `DSTRecordDecoder`, used by the round-trip tests. Like the
/// decoder, no product feature reads DST in M1–M6, so this stays in the
/// test target. Layout constants (512-byte header, 3-byte records, the
/// `00 00 F3` end-of-file record) are deliberately hard-coded literals —
/// an independent oracle must not reuse the writer's definitions.
struct DecodedDSTFile {
    /// Header tag → value with its in-field padding stripped.
    var headerFields: [String: String]
    var records: [DSTRecordDecoder.DecodedRecord]
    /// Absolute stitch positions accumulated from the record deltas, with
    /// the origin at the first stitch (DST stores only relative moves).
    var positions: [EmbroideryPoint]

    func headerValue(_ tag: String) -> Int? {
        headerFields[tag].flatMap(Int.init)
    }
}

enum DSTFileReader {
    static func read(_ data: Data) throws -> DecodedDSTFile {
        let bytes = Array(data)
        try #require(bytes.count >= 515, "shorter than header + end-of-file record")
        try #require((bytes.count - 515) % 3 == 0, "record region is not a whole number of records")
        try #require(Array(bytes.suffix(3)) == [0x00, 0x00, 0xF3], "missing end-of-file record")

        var records: [DSTRecordDecoder.DecodedRecord] = []
        var positions: [EmbroideryPoint] = []
        var position = EmbroideryPoint(x: 0, y: 0)
        for offset in stride(from: 512, to: bytes.count - 3, by: 3) {
            let record = DSTRecordDecoder.decode(Array(bytes[offset ..< offset + 3]))
            records.append(record)
            position = EmbroideryPoint(x: position.x + record.dx, y: position.y + record.dy)
            positions.append(position)
        }
        return try DecodedDSTFile(
            headerFields: fields(in: Array(bytes.prefix(512))),
            records: records,
            positions: positions
        )
    }

    /// Walks the 124 content bytes as `TAG:value` fields, each terminated
    /// by `\n` + 0x1A, and strips the value's NUL/space padding.
    private static func fields(in header: [UInt8]) throws -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index < 124 {
            let tag = String(decoding: header[index ..< index + 2], as: UTF8.self)
            try #require(header[index + 2] == UInt8(ascii: ":"), "malformed field tag \(tag)")
            var end = index + 3
            while end < 124, header[end] != 0x0A {
                end += 1
            }
            try #require(header[end] == 0x0A && header[end + 1] == 0x1A, "field \(tag) lacks its terminator")
            let value = header[index + 3 ..< end].filter { $0 != 0x00 }
            result[tag] = String(decoding: value, as: UTF8.self)
                .trimmingCharacters(in: .whitespaces)
            index = end + 2
        }
        return result
    }
}
