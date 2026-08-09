import Foundation
import ProgramModel
import Samples
import Testing

@Suite("Sample library")
struct SampleLibraryTests {
    /// Story item 1 — ADR-008's paired-control invariant holds for every script
    /// in every sample. An unbalanced script compiles to an inert instruction
    /// list (ADR-018), so a sample that failed this would animate as nothing at
    /// all rather than crash — which is exactly why it is asserted here.
    @Test("every script balances its paired control bricks", arguments: SampleLibrary.all)
    func everyScriptValidates(_ sample: SampleProgram) throws {
        let scripts = sample.program.scenes.flatMap(\.objects).flatMap(\.scripts)
        #expect(!scripts.isEmpty, "\(sample.id.rawValue) has no scripts to run")
        for script in scripts {
            try script.validate()
        }
    }

    /// US-304 leans on this: it declares the picker's empty state unreachable by
    /// construction, and asks for the claim to be asserted rather than assumed.
    @Test("the library is not empty")
    func libraryIsNotEmpty() {
        #expect(!SampleLibrary.all.isEmpty)
    }

    /// `SampleLibrary[id]` is documented as total. That is only true while `all`
    /// covers every case, so pin it here rather than trusting the subscript's
    /// `preconditionFailure` to be unreachable.
    @Test("ids are unique and cover every SampleID case")
    func idsAreUniqueAndTotal() {
        let ids = SampleLibrary.all.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate sample id in SampleLibrary.all")
        #expect(Set(ids) == Set(SampleID.allCases))
    }

    /// The keys are derived from the id so the two cannot drift. Pinning the
    /// format here means a rename breaks a package test instead of silently
    /// showing a raw key in the picker.
    @Test("localization keys are derived from the id", arguments: SampleLibrary.all)
    func keysFollowTheIDFormat(_ sample: SampleProgram) {
        #expect(sample.nameKey == "sample.\(sample.id.rawValue).name")
        #expect(sample.descriptionKey == "sample.\(sample.id.rawValue).description")
    }

    /// The strings ship in this target's own bundle, so — unlike a bare key
    /// handed to someone else's catalog — the package can prove they resolve.
    /// Resolving to the key itself is the failure this catches.
    @Test("name and description resolve to real text, not to the key", arguments: SampleLibrary.all)
    func localizedStringsResolve(_ sample: SampleProgram) {
        let name = String(localized: sample.displayName)
        let summary = String(localized: sample.summary)
        #expect(name != sample.nameKey, "\(sample.nameKey) did not resolve")
        #expect(summary != sample.descriptionKey, "\(sample.descriptionKey) did not resolve")
        #expect(!name.isEmpty)
        #expect(!summary.isEmpty)
    }

    /// Forward guard for US-308, which writes the design name into the DST `LA:`
    /// field: ADR-012 pins that at 15 characters, and Catty's 16-char truncation
    /// is on the never-port list. Costs nothing here and stops a sample from
    /// being the thing that discovers the limit.
    @Test("every program name fits the DST label field", arguments: SampleLibrary.all)
    func programNameFitsTheDSTLabel(_ sample: SampleProgram) {
        let name = sample.program.name
        #expect(!name.isEmpty)
        #expect(name.count <= 15, "\(name) exceeds ADR-012's 15-character LA: field")
        let isASCII = name.allSatisfy(\.isASCII)
        #expect(isASCII, "\(name) is not ASCII-safe for the LA: field")
    }
}
