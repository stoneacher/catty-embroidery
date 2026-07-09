import Testing

// Byte-level diff helpers for the golden-file tests (US-106): a raw
// `#expect(a == b)` on two ~580-byte arrays dumps both blobs unreadably,
// and byte-diff debugging without offsets "is where days go" (story risk
// note). `firstByteDifference` is a pure function so the differ itself is
// unit-testable; `expectBytesEqual` is the assertion wrapper.

/// Returns `nil` when the arrays are equal; otherwise a message naming the
/// first mismatching offset (decimal and hex), the differing bytes, any
/// length mismatch, and a ±8-byte hex window of both sides.
func firstByteDifference(actual: [UInt8], expected: [UInt8]) -> String? {
    guard actual != expected else { return nil }
    let sharedCount = min(actual.count, expected.count)
    let offset = (0 ..< sharedCount).first { actual[$0] != expected[$0] } ?? sharedCount

    var lines: [String] = []
    if actual.count != expected.count {
        lines.append("length mismatch: actual \(actual.count) bytes, expected \(expected.count) bytes")
    }
    lines.append(
        String(format: "first mismatch at offset %d (0x%X): ", offset, offset)
            + "actual \(byteDescription(actual, at: offset)), expected \(byteDescription(expected, at: offset))"
    )
    lines.append("actual   " + hexWindow(actual, around: offset))
    lines.append("expected " + hexWindow(expected, around: offset))
    return lines.joined(separator: "\n")
}

/// Asserts byte equality via `firstByteDifference`, recording a focused
/// issue at the caller's line instead of dumping both blobs.
func expectBytesEqual(
    _ actual: some Sequence<UInt8>,
    _ expected: some Sequence<UInt8>,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    if let message = firstByteDifference(actual: Array(actual), expected: Array(expected)) {
        Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
    }
}

private func byteDescription(_ bytes: [UInt8], at offset: Int) -> String {
    offset < bytes.count ? String(format: "0x%02X", bytes[offset]) : "end of data"
}

/// Hex dump of the bytes within ±8 positions of `offset`, the byte at
/// `offset` bracketed.
private func hexWindow(_ bytes: [UInt8], around offset: Int) -> String {
    let lower = max(0, offset - 8)
    let upper = min(bytes.count, offset + 9)
    guard lower < upper else { return "(no bytes at offset)" }
    let hex = (lower ..< upper).map { index in
        let byte = String(format: "%02x", bytes[index])
        return index == offset ? "[\(byte)]" : byte
    }
    return "bytes \(lower)..<\(upper): " + hex.joined(separator: " ")
}
