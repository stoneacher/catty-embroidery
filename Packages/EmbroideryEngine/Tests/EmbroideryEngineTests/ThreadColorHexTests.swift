import EmbroideryEngine
import Testing

@Suite("ThreadColor hex parsing")
struct ThreadColorHexTests {
    // Port of Catroid `SetThreadColorAction` (ADR-012): characters [1,3),
    // [3,5), [5,7) are the RR/GG/BB hex bytes. Index 0 is skipped without
    // being validated (Android substrings from index 1 regardless of what
    // the first character is), and anything past index 7 is ignored. Any
    // malformed input parses to nil so the caller leaves the current color
    // unchanged — Android swallows the parse exception and keeps the
    // sprite's color (ADR-015 pin: even its null-formula default "0xff0000"
    // throws internally and no-ops).

    @Test("parses #RRGGBB into RGB bytes")
    func uppercaseHex() {
        #expect(ThreadColor(hexString: "#FF0000") == ThreadColor(red: 255, green: 0, blue: 0))
        #expect(ThreadColor(hexString: "#00FF7F") == ThreadColor(red: 0, green: 255, blue: 127))
    }

    @Test("lowercase and mixed-case hex digits parse")
    func caseInsensitive() {
        #expect(ThreadColor(hexString: "#ff00ff") == ThreadColor(red: 255, green: 0, blue: 255))
        #expect(ThreadColor(hexString: "#aBcDeF") == ThreadColor(red: 0xAB, green: 0xCD, blue: 0xEF))
    }

    @Test("the leading character is skipped, not validated")
    func prefixIgnored() {
        #expect(ThreadColor(hexString: "xFF0000") == ThreadColor(red: 255, green: 0, blue: 0))
    }

    @Test("indexing is by UTF-16 code units, matching Java String.substring")
    func utf16Indexing() {
        // swift-code-reviewer US-110 find: Java's substring counts UTF-16
        // code units, not bytes. "€" is one unit (three UTF-8 bytes), so
        // Android parses "€FF0000" to red; a surrogate half or a non-ASCII
        // unit inside the pair region is never a hex digit and no-ops.
        #expect(ThreadColor(hexString: "€FF0000") == ThreadColor(red: 255, green: 0, blue: 0))
        #expect(ThreadColor(hexString: "😀FF0000") == nil) // low surrogate lands at index 1
        #expect(ThreadColor(hexString: "#€F0000") == nil)
    }

    @Test("characters beyond index 7 are ignored — alpha is discarded")
    func trailingIgnored() {
        #expect(ThreadColor(hexString: "#11223344") == ThreadColor(red: 0x11, green: 0x22, blue: 0x33))
        #expect(ThreadColor(hexString: "#000000 with trailing junk") == .black)
    }

    /// "#+12345"/"#-12345" pin Java semantics: `Integer.decode("0x+1")`
    /// throws (sign only allowed before the radix prefix), while Swift's
    /// `UInt8("+1", radix:)` would accept it — the parser must reject signs.
    @Test("malformed input returns nil so the caller keeps the current color", arguments: [
        "", "#", "#ff", "#ff00", "#ff000", "#gg0000", "#ff 000", "0xff0000",
        "#+12345", "#-12345"
    ])
    func malformedInput(hex: String) {
        #expect(ThreadColor(hexString: hex) == nil)
    }
}
