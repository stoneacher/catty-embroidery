@testable import EmbroideryEngine
import Testing

@Suite("DST stitch record encoder")
struct DSTStitchRecordTests {
    /// Hand-computed against the DST bit chart (see DSTRecordDecoder), the
    /// ±121 vectors against the balanced-ternary decomposition 121 = 81+27+9+3+1.
    /// (-40,-40) matches Catroid DSTStitchPointTest.testStitchBytesDifference
    /// (stage delta -20 × unit factor 2).
    private static let knownDeltas: [(dx: Int, dy: Int)] = [
        (0, 0),
        (1, 0),
        (0, 1),
        (-1, -1),
        (121, 0),
        (0, -121),
        (-40, -40)
    ]
    private static let knownBytes: [[UInt8]] = [
        [0x00, 0x00, 0x03],
        [0x01, 0x00, 0x03],
        [0x80, 0x00, 0x03],
        [0x42, 0x00, 0x03],
        [0x05, 0x05, 0x07],
        [0x50, 0x50, 0x13],
        [0x5A, 0x5A, 0x03]
    ]

    @Test("known vectors encode to the reference bytes", arguments: zip(knownDeltas, knownBytes))
    func encodesKnownVectors(delta: (dx: Int, dy: Int), expected: [UInt8]) {
        let record = DSTStitchRecord(dx: delta.dx, dy: delta.dy)
        #expect(record.bytes == expected)
    }

    @Test("jump sets 0x80 in byte 3")
    func jumpFlag() {
        #expect(DSTStitchRecord(dx: 0, dy: 0, isJump: true).bytes == [0x00, 0x00, 0x83])
        // Catroid DSTStitchPointTest.testStitchBytesWithJump: stage (0,0)
        // relative to (20,-20) → unit delta (-40, +40).
        #expect(DSTStitchRecord(dx: -40, dy: 40, isJump: true).bytes == [0xAA, 0xAA, 0x83])
    }

    @Test("color change sets 0xC0 in byte 3")
    func colorChangeFlag() {
        #expect(DSTStitchRecord(dx: 0, dy: 0, isColorChange: true).bytes == [0x00, 0x00, 0xC3])
        // Catroid DSTStitchPointTest.testStitchBytesWithColorChange: stage
        // (0,0) relative to (-20,-20) → unit delta (+40, +40).
        #expect(DSTStitchRecord(dx: 40, dy: 40, isColorChange: true).bytes == [0xA5, 0xA5, 0xC3])
    }

    @Test("every in-range delta round-trips through the test decoder")
    func exhaustiveRoundTrip() {
        // One plain loop on purpose: 243×243 parameterized cases would
        // drown the test report (US-103 test-first plan).
        for dx in -121 ... 121 {
            for dy in -121 ... 121 {
                let decoded = DSTRecordDecoder.decode(DSTStitchRecord(dx: dx, dy: dy).bytes)
                #expect(decoded == .init(dx: dx, dy: dy, isJump: false, isColorChange: false))
                if decoded.dx != dx || decoded.dy != dy {
                    return // one failing delta is enough diagnosis; don't spam 59k failures
                }
            }
        }
    }

    @Test("flags round-trip through the test decoder")
    func flagRoundTrip() {
        let jump = DSTRecordDecoder.decode(DSTStitchRecord(dx: 7, dy: -3, isJump: true).bytes)
        #expect(jump == .init(dx: 7, dy: -3, isJump: true, isColorChange: false))

        let colorChange = DSTRecordDecoder.decode(DSTStitchRecord(dx: -7, dy: 3, isColorChange: true).bytes)
        #expect(colorChange == .init(dx: -7, dy: 3, isJump: false, isColorChange: true))
    }

    @Test("conversion table matches its balanced-ternary derivation")
    func conversionTableRegeneration() {
        /// The algorithmic derivation lives only here (US-103): the product
        /// table is Catroid's data verbatim; this test regenerates it from
        /// the bit meaning (0x1=+1, 0x2=-1, 0x4=+3, 0x8=-3, ... 0x200=-81).
        func derivedEntry(for value: Int) -> UInt16 {
            var remainder = value
            var entry: UInt16 = 0
            for level in 0 ..< 5 {
                let digit = (remainder % 3 + 3) % 3
                if digit == 1 {
                    entry |= 1 << (2 * level)
                    remainder -= 1
                } else if digit == 2 {
                    entry |= 1 << (2 * level + 1)
                    remainder += 1
                }
                remainder /= 3
            }
            precondition(remainder == 0, "value out of ±121 range")
            return entry
        }

        var derivedTable = (0 ... 121).map(derivedEntry(for:))
        derivedTable += (1 ... 121).map { derivedEntry(for: -$0) }
        #expect(DSTStitchRecord.conversionTable == derivedTable)
    }

    @Test("deltas outside ±121 are rejected")
    func rejectsOutOfRangeDeltas() async {
        // Literal deltas per expectation: an exit-test body runs in a fresh
        // process and must not capture the enclosing context.
        await #expect(processExitsWith: .failure) { _ = DSTStitchRecord(dx: 122, dy: 0) }
        await #expect(processExitsWith: .failure) { _ = DSTStitchRecord(dx: -122, dy: 0) }
        await #expect(processExitsWith: .failure) { _ = DSTStitchRecord(dx: 0, dy: 122) }
        await #expect(processExitsWith: .failure) { _ = DSTStitchRecord(dx: 0, dy: -122) }
    }

    @Test("the boundary ±121 deltas are legal (Catty's strict guard is a bug)")
    func acceptsBoundaryDeltas() {
        // ADR-012: do not port Catty's strict-comparison rejection of ±121.
        let decoded = DSTRecordDecoder.decode(DSTStitchRecord(dx: 121, dy: -121).bytes)
        #expect(decoded == .init(dx: 121, dy: -121, isJump: false, isColorChange: false))
    }

    @Test("deltas come from individually converted positions, not converted differences")
    func roundThenSubtract() {
        // Stage x = ±0.2 → units floor(±0.4 + 0.5) = 0 each, so the delta
        // is 0; converting the stage difference (0.4 → 1 unit) would give 1
        // (ADR-012: round-then-subtract).
        let previous = EmbroideryPoint(converting: StagePoint(x: -0.2, y: 0))
        let current = EmbroideryPoint(converting: StagePoint(x: 0.2, y: 0))
        let record = DSTStitchRecord(from: previous, to: current)
        #expect(record.bytes == [0x00, 0x00, 0x03])
    }
}
