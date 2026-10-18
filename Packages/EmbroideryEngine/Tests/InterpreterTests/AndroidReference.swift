import EmbroideryEngine
import Foundation
import Testing

/// Reading the Android reference exports (`Resources/AndroidReference`) and our
/// own DST output back into absolute stitch positions, so the two can be
/// compared per stitch (Brick backend, slices 4–5).
enum AndroidReference {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name,
            withExtension: "dst",
            subdirectory: "Resources/AndroidReference"
        ))
        return try Data(contentsOf: url)
    }
}

/// One decoded DST record: its kind and the absolute position it moves to, in
/// DST units (0.1 mm).
struct DSTRecordPosition: Equatable, CustomStringConvertible {
    enum Kind: Equatable { case stitch, jump, colorChange, end }

    let kind: Kind
    let x: Int
    let y: Int

    var description: String {
        "\(kind)(\(x), \(y))"
    }
}

/// Decodes the 3-byte Tajima records after the 512-byte header (ADR-012's
/// layout), accumulating the deltas into absolute positions. Stops at the end
/// record. Written independently of the engine's encoder, so a shared mistake
/// cannot make the comparison agree with itself.
func decodeRecordPositions(_ data: Data) -> [DSTRecordPosition] {
    let bytes = [UInt8](data.dropFirst(512))
    var positions: [DSTRecordPosition] = []
    var x = 0
    var y = 0
    var index = 0
    while index + 2 < bytes.count {
        let (first, second, third) = (bytes[index], bytes[index + 1], bytes[index + 2])
        index += 3
        x += deltaX(first, second, third)
        y += deltaY(first, second, third)
        // The end record is exact (`00 00 F3`). Otherwise the kind is the third byte's
        // control bits alone: `0xC3` drops the ±81 displacement bits (0x30) and the ±81
        // X bits (0x0C), which `0xF3` kept, reading a jump of (0, −81) as a stitch.
        let kind: DSTRecordPosition.Kind = if (first, second, third) == (0x00, 0x00, 0xF3) {
            .end
        } else {
            switch third & 0xC3 {
            case 0x83: .jump
            case 0xC3: .colorChange
            default: .stitch
            }
        }
        positions.append(DSTRecordPosition(kind: kind, x: x, y: y))
        if kind == .end {
            break
        }
    }
    return positions
}

private func bit(_ byte: UInt8, _ mask: UInt8, _ value: Int) -> Int {
    byte & mask == 0 ? 0 : value
}

private func deltaX(_ first: UInt8, _ second: UInt8, _ third: UInt8) -> Int {
    bit(first, 0x01, 1) - bit(first, 0x02, 1) + bit(first, 0x04, 9) - bit(first, 0x08, 9)
        + bit(second, 0x01, 3) - bit(second, 0x02, 3) + bit(second, 0x04, 27) - bit(second, 0x08, 27)
        + bit(third, 0x04, 81) - bit(third, 0x08, 81)
}

private func deltaY(_ first: UInt8, _ second: UInt8, _ third: UInt8) -> Int {
    bit(first, 0x80, 1) - bit(first, 0x40, 1) + bit(first, 0x20, 9) - bit(first, 0x10, 9)
        + bit(second, 0x80, 3) - bit(second, 0x40, 3) + bit(second, 0x20, 27) - bit(second, 0x10, 27)
        + bit(third, 0x20, 81) - bit(third, 0x10, 81)
}

/// The header fields Android wrote, read as text (`ST:`, `+X:` …, `AX:`), so the
/// decoder is checked against the exporter's own numbers rather than itself.
struct DSTHeaderSummary: Equatable {
    let stitches: Int
    let plusX: Int, minusX: Int, plusY: Int, minusY: Int
    let endX: Int, endY: Int

    init(header data: Data) throws {
        // Android ends each field with `\n` and starts the next with `0x1A`, and pads
        // values with NULs (`ST:40\0\0\0\0\0\n\u{1A}CO:1…`), so both are stripped.
        let padding = CharacterSet(charactersIn: "\u{0}\u{1A}\r ")
        let lines = (String(bytes: data.prefix(512), encoding: .utf8) ?? "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: padding) }
        func field(_ name: String) throws -> Int {
            let line = try #require(lines.first { $0.hasPrefix(name) }, "no \(name) field")
            return try #require(Int(line.dropFirst(name.count).trimmingCharacters(in: padding)))
        }
        stitches = try field("ST:")
        plusX = try field("+X:")
        minusX = try field("-X:")
        plusY = try field("+Y:")
        minusY = try field("-Y:")
        endX = try field("AX:")
        endY = try field("AY:")
    }

    /// The same summary computed from decoded records: stitches and jumps
    /// counted, the extents of every position, the last position.
    init(records: [DSTRecordPosition]) {
        let moving = records.filter { $0.kind != .end }
        stitches = moving.count
        plusX = moving.map(\.x).max() ?? 0
        minusX = -(moving.map(\.x).min() ?? 0)
        plusY = moving.map(\.y).max() ?? 0
        minusY = -(moving.map(\.y).min() ?? 0)
        endX = records.last?.x ?? 0
        endY = records.last?.y ?? 0
    }
}
