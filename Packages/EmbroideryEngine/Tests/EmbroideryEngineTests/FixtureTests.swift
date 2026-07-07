import Foundation
import Testing

/// The reference DST fixtures (see Resources/EmbroideryReference/PROVENANCE.md)
/// must be reachable via `Bundle.module` and byte-identical to the Catty originals,
/// as golden tests in US-104/US-106 diff against them byte by byte.
struct FixtureTests {
    @Test(arguments: [("stitch", 539), ("color_change", 581)])
    func fixtureIsBundledAndIntact(name: String, byteCount: Int) throws {
        let url = try #require(Bundle.module.url(
            forResource: name,
            withExtension: "dst",
            subdirectory: "Resources/EmbroideryReference"
        ))
        let data = try Data(contentsOf: url)
        #expect(data.count == byteCount)
    }
}
