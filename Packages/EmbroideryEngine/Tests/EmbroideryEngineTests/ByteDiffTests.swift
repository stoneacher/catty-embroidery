import Testing

@Suite("Byte diff helper")
struct ByteDiffTests {
    @Test("equal arrays produce no difference")
    func equalArrays() {
        #expect(firstByteDifference(actual: [0x00, 0x01, 0xF3], expected: [0x00, 0x01, 0xF3]) == nil)
        #expect(firstByteDifference(actual: [], expected: []) == nil)
    }

    @Test("a mid-array flip reports its offset in decimal and hex, with both bytes")
    func midArrayFlip() throws {
        var actual = Array(UInt8(0) ..< 40)
        actual[18] = 0xC3
        let message = try #require(firstByteDifference(actual: actual, expected: Array(UInt8(0) ..< 40)))
        #expect(message.contains("offset 18 (0x12)"))
        #expect(message.contains("actual 0xC3, expected 0x12"))
        #expect(!message.contains("length mismatch"))
    }

    @Test("hex windows bracket the mismatching byte on both sides")
    func hexWindowContext() throws {
        var actual = Array(repeating: UInt8(0x20), count: 24)
        actual[12] = 0x83
        let expected = Array(repeating: UInt8(0x20), count: 24)
        let message = try #require(firstByteDifference(actual: actual, expected: expected))
        #expect(message.contains("actual   bytes 4..<21: 20 20 20 20 20 20 20 20 [83] 20 20 20 20 20 20 20 20"))
        #expect(message.contains("expected bytes 4..<21: 20 20 20 20 20 20 20 20 [20] 20 20 20 20 20 20 20 20"))
    }

    @Test("a longer actual reports the length mismatch and the tail offset")
    func actualLonger() throws {
        let message = try #require(firstByteDifference(actual: [1, 2, 3, 4], expected: [1, 2, 3]))
        #expect(message.contains("length mismatch: actual 4 bytes, expected 3 bytes"))
        #expect(message.contains("offset 3 (0x3)"))
        #expect(message.contains("actual 0x04, expected end of data"))
    }

    @Test("a shorter actual reports the length mismatch and where it ends")
    func actualShorter() throws {
        let message = try #require(firstByteDifference(actual: [1, 2], expected: [1, 2, 3]))
        #expect(message.contains("length mismatch: actual 2 bytes, expected 3 bytes"))
        #expect(message.contains("offset 2 (0x2)"))
        #expect(message.contains("actual end of data, expected 0x03"))
    }
}
