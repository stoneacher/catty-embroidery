import Foundation
import ProgramModel
import Samples
import Testing

/// Regenerates the checked-in JSON resources from the Swift builders.
///
/// **Off unless `REGENERATE_SAMPLE_JSON` names a directory.** The resources are
/// build inputs, so a test that rewrote them on every run would defeat the very
/// guard they exist for — `checkedInResourceMatchesTheBuilder` would then always
/// pass, comparing a file it had just written against the builder that wrote it.
///
///     REGENERATE_SAMPLE_JSON=Sources/Samples/Resources \
///       swift test --package-path Packages/EmbroideryEngine \
///       --filter "Sample resource regeneration"
///
/// When that comparison goes red, **decide whether the builder change is correct
/// before running this.** Regenerating is how a resource guard gets silently
/// defeated.
@Suite(
    "Sample resource regeneration",
    .enabled(if: ProcessInfo.processInfo.environment["REGENERATE_SAMPLE_JSON"] != nil)
)
struct SampleResourceRegenerationTests {
    @Test("write each sample's program to its JSON resource", arguments: SampleLibrary.all)
    func regenerate(_ sample: SampleProgram) throws {
        let directory = try #require(ProcessInfo.processInfo.environment["REGENERATE_SAMPLE_JSON"])
        let encoder = JSONEncoder()
        // Deterministic and readable, so a builder change shows up as a legible
        // diff rather than as one reordered line.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        let url = URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent("\(sample.id.resourceName).json")
        try encoder.encode(sample.program).write(to: url)
        print("US-301 regenerated \(url.path)")
    }
}
