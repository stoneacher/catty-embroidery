import EditorCore
import EmbroideryEngine
import ProgramModel
import Samples
import Testing

/// US-410 test-first item 8, the data half of ADR-040: the curated thread
/// palette is a fixed list of hex strings, written verbatim into
/// `setThreadColor(hex:)` — no colour type in between to round-trip through.
@Suite("Thread palette")
struct ThreadPaletteTests {
    /// Every swatch must be a value ADR-015's parser already accepts, so the
    /// palette can never start exercising the invalid-hex no-op path.
    @Test("every swatch parses through the thread-colour parser", arguments: ThreadSwatch.allCases)
    func parses(swatch: ThreadSwatch) {
        #expect(ThreadColor(hexString: swatch.hex) != nil)
    }

    /// One spelling: `#` plus six lowercase hex digits, the form the template
    /// and both samples use, so equality with a stored brick is string equality.
    @Test("every swatch is spelled #rrggbb in lowercase", arguments: ThreadSwatch.allCases)
    func spelling(swatch: ThreadSwatch) {
        let hex = swatch.hex
        #expect(hex.count == 7)
        #expect(hex.first == "#")
        #expect(hex.dropFirst().allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test("no two swatches share a colour")
    func distinct() {
        let hexes = ThreadSwatch.allCases.map(\.hex)
        #expect(Set(hexes).count == hexes.count)
    }

    /// The template's colour and every colour a shipped sample stores are in
    /// the palette, so opening any of those bricks shows a selected swatch
    /// rather than an unexplained "current" one.
    @Test("the default and every sample colour are swatches")
    func coversShippedColours() {
        var shipped: Set<String> = [BrickDefaults.threadColorHex]
        for sample in SampleLibrary.all {
            for brick in sample.program.scenes.flatMap(\.objects).flatMap(\.scripts).flatMap(\.bricks) {
                if case let .setThreadColor(hex) = brick {
                    shipped.insert(hex)
                }
            }
        }
        let palette = Set(ThreadSwatch.allCases.map(\.hex))
        #expect(shipped.isSubset(of: palette), "missing: \(shipped.subtracting(palette).sorted())")
    }

    @Test("a stored hex finds its swatch by exact spelling only")
    func lookup() {
        #expect(ThreadSwatch(hex: BrickDefaults.threadColorHex)?.hex == BrickDefaults.threadColorHex)
        #expect(ThreadSwatch(hex: "#FF0000") == nil)
        #expect(ThreadSwatch(hex: "#123456") == nil)
    }

    /// Item 8 proper: the brick a swatch produces carries the swatch's string,
    /// byte for byte.
    @Test("item 8: a swatch choice replaces the brick with the exact hex string", arguments: ThreadSwatch.allCases)
    func choice(swatch: ThreadSwatch) {
        #expect(
            Brick.setThreadColor(hex: "#000001").replacing(.hex, with: .threadColor(hex: swatch.hex))
                == .setThreadColor(hex: swatch.hex)
        )
    }
}
