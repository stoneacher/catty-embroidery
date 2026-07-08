@testable import EmbroideryEngine

/// Test-only decoder for 3-byte DST stitch records. No product feature
/// reads DST in M1–M6 (US-103), so this lives in the test target; promote
/// it as its own story if export validation ever needs to re-read files.
///
/// Decodes straight off the DST bit chart (no conversion table needed):
///
///     BYTE  |  7  |  6  |  5  |  4  ||  3  |  2  |  1  |  0
///     ------|------------------------------------------------
///       1   | y+1 | y-1 | y+9 | y-9 || x-9 | x+9 | x-1 | x+1
///       2   | y+3 | y-3 | y+27| y-27|| x-27| x+27| x-3 | x+3
///       3   | c2  | c1  | y+81| y-81|| x-81| x+81| set | set
enum DSTRecordDecoder {
    struct DecodedRecord: Equatable {
        var dx: Int
        var dy: Int
        var isJump: Bool
        var isColorChange: Bool
    }

    static func decode(_ bytes: [UInt8]) -> DecodedRecord {
        precondition(bytes.count == 3, "a DST stitch record is exactly 3 bytes")
        let contributions: [(byte: Int, bit: Int, dx: Int, dy: Int)] = [
            (0, 0, 1, 0), (0, 1, -1, 0), (0, 2, 9, 0), (0, 3, -9, 0),
            (0, 4, 0, -9), (0, 5, 0, 9), (0, 6, 0, -1), (0, 7, 0, 1),
            (1, 0, 3, 0), (1, 1, -3, 0), (1, 2, 27, 0), (1, 3, -27, 0),
            (1, 4, 0, -27), (1, 5, 0, 27), (1, 6, 0, -3), (1, 7, 0, 3),
            (2, 2, 81, 0), (2, 3, -81, 0), (2, 4, 0, -81), (2, 5, 0, 81)
        ]

        var dx = 0
        var dy = 0
        for contribution in contributions where bytes[contribution.byte] & (1 << contribution.bit) != 0 {
            dx += contribution.dx
            dy += contribution.dy
        }

        let isColorChange = bytes[2] & 0xC0 == 0xC0
        let isJump = bytes[2] & 0x80 != 0 && !isColorChange
        return DecodedRecord(dx: dx, dy: dy, isJump: isJump, isColorChange: isColorChange)
    }
}
