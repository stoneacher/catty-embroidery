import Foundation
import ProgramModel
import Samples
import Testing

/// Story item 6 — the JSON encoding that M5 inherits (ADR-003).
@Suite("Sample JSON resources")
struct SampleJSONResourceTests {
    /// `Program`'s `==` chain is NaN-aware all the way down (Program → Object →
    /// Variable → Formula), so whole-value equality is reflexive and this is a
    /// single expectation rather than a field-by-field walk.
    @Test("a sample program survives an encode/decode round trip unchanged", arguments: SampleLibrary.all)
    func programRoundTripsThroughJSON(_ sample: SampleProgram) throws {
        let data = try JSONEncoder().encode(sample.program)
        let decoded = try JSONDecoder().decode(Program.self, from: data)
        #expect(decoded == sample.program)
    }

    /// The checked-in resource must decode equal to the builder. The builder is
    /// the single source of truth; a resource that disagrees is a failing test,
    /// not a second opinion.
    ///
    /// This is also the `formatVersion` tripwire the story asks for, and it works
    /// for free: `Program.formatVersion` is encoded, so bumping
    /// `currentFormatVersion` without regenerating makes the comparison go red
    /// instead of leaving a stale resource to rot.
    @Test("the checked-in resource decodes equal to its builder", arguments: SampleLibrary.all)
    func checkedInResourceMatchesTheBuilder(_ sample: SampleProgram) throws {
        let url = try #require(sample.programJSONURL, "no JSON resource shipped for \(sample.id.rawValue)")
        let decoded = try JSONDecoder().decode(Program.self, from: Data(contentsOf: url))
        #expect(decoded == sample.program)
        #expect(decoded.formatVersion == Program.currentFormatVersion)
    }
}
