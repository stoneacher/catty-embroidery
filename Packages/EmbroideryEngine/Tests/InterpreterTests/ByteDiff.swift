import Testing

// Deliberate copy of `Tests/EmbroideryEngineTests/ByteDiff.swift` (US-209).
//
// The canonical file is the one in `EmbroideryEngineTests`; it owns the unit
// tests (`ByteDiffTests.swift`, which exercises `firstByteDifference`). This is
// a duplicate, not a fork: keep the two identical.
//
// Why duplicated rather than shared: SwiftPM does not let one test target
// depend on another, so sharing would mean a plain target under `Sources/` —
// test-only code in the shipped source tree, and `import Testing` in a library
// target's build graph. Splitting the pure differ out to avoid that still
// leaves `expectBytesEqual` duplicated per target. For a package headed
// upstream to Catrobat, a self-contained copy inside a test target is the
// smaller and more explicable cost (US-209 planning, Sebastian).
//
// Promotion trigger: if a third target needs these helpers, promote them to a
// shared test-support target then, rather than adding a third copy. The second
// candidate for that target already exists — DST header-field reading, which the
// same SwiftPM constraint has now produced three times (`DSTHeaderTests.fields`,
// `DSTFileReader.fields`, and `dstHeaderField` here).

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
