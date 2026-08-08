import EmbroideryEngine
import Foundation

// A minimal DST header reader for the sample suites: just the two fields US-301
// asserts (`CO` and `ST`).
//
// A third copy of this idea now exists — `InterpreterTests/DSTHeaderFieldReader`
// and `EmbroideryEngineTests/DSTFileReader` are the others. SwiftPM forbids
// test-target-to-test-target dependencies, and sharing would mean test-only code
// under `Sources/` plus `import Testing` in a library target, so the copies
// cross-reference each other instead. This one is deliberately the smallest of
// the three: it reads two fields, not nine.
//
// The offsets are **hard-coded from the Tajima layout, not derived from
// `DSTHeader`** — the same discipline the other two readers state: an oracle must
// not reuse the writer's definitions, or it cannot detect the writer moving.
// Layout: each field is `TAG:` (3) + value + padding-to-width + `\n` + 0x1A (2).
// LA is 15 wide, ST 6, CO 2 — so ST's tag sits at 20 and CO's at 20 + 11 = 31.

private let stitchCountTagOffset = 20
private let colorBlocksTagOffset = 31

/// The `CO` field — DST colour *blocks*, which ADR-012 pins as changes + 1.
func coField(of header: DSTHeader) -> Int? {
    numericField(header.bytes, tagOffset: colorBlocksTagOffset, tag: "CO", width: 2)
}

/// The `ST` field — the record count.
func stField(of header: DSTHeader) -> Int? {
    numericField(header.bytes, tagOffset: stitchCountTagOffset, tag: "ST", width: 6)
}

/// Reads a NUL-padded numeric field, returning `nil` if the tag is not where the
/// layout says it should be — so a shifted header surfaces as a missing field
/// rather than as a plausible wrong number.
private func numericField(_ bytes: [UInt8], tagOffset: Int, tag: String, width: Int) -> Int? {
    let valueStart = tagOffset + 3
    guard bytes.count >= valueStart + width else { return nil }
    guard String(bytes: bytes[tagOffset ..< tagOffset + 2], encoding: .utf8) == tag else { return nil }

    var value = Array(bytes[valueStart ..< valueStart + width])
    while value.last == 0x00 {
        value.removeLast()
    }
    guard let text = String(bytes: value, encoding: .utf8) else { return nil }
    return Int(text.trimmingCharacters(in: .whitespaces))
}
