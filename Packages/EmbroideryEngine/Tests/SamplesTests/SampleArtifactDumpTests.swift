import EmbroideryEngine
import Foundation
import Samples
import Testing

/// Writes both samples' DST files so they can be opened in an embroidery viewer
/// — the manual Ink/Stitch verification the milestone requires at this story.
///
/// **Off unless `DUMP_SAMPLE_DST` is set.** Tests run in parallel and the
/// pre-commit hook runs the whole suite on every commit, so a suite that always
/// wrote files would have both a shared-path hazard and a side effect nobody
/// asked for. The output directory is per-run and unique for the same reason.
///
///     DUMP_SAMPLE_DST=1 swift test --package-path Packages/EmbroideryEngine
@Suite(
    "Sample DST artifacts",
    .enabled(if: ProcessInfo.processInfo.environment["DUMP_SAMPLE_DST"] != nil)
)
struct SampleArtifactDumpTests {
    @Test("write each sample's DST to a unique temp directory", arguments: SampleLibrary.all)
    func dump(_ sample: SampleProgram) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("us-301-samples-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let measured = run(sample)
        let file = DSTFile(stream: measured.stream, name: sample.program.name)
        let url = directory.appendingPathComponent("\(sample.id.resourceName).dst")
        try file.write(to: url)

        let bounds = stageBounds(of: measured.stream)
        let extent = extentInMillimetres(of: measured.stream)
        print("""
        US-301 artifact — \(sample.id.rawValue)
          path      \(url.path)
          bytes     \(file.data.count)
          records   \(measured.stream.count)
          colours   \(measured.stream.colorChangeCount + 1)
          jumps     \(measured.stream.stitches.count(where: \.isJump))
          size      \(extent.map { "\($0.width) x \($0.height) mm" } ?? "empty")
          stage     \(bounds.map { "x [\($0.minX), \($0.maxX)] y [\($0.minY), \($0.maxY)]" } ?? "empty")
        """)
    }
}
