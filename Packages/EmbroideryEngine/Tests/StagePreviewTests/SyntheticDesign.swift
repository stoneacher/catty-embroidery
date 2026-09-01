import EmbroideryEngine
import ProgramModel
import Samples
import StagePreview

/// US-309's measurement fixture: a 50 000-stitch design, in both of the shapes the story
/// needs.
///
/// **It lives in the test target, not in `StagePreview` or in `Samples`**, and both
/// exclusions were decided rather than defaulted:
///
/// - The story says "`SyntheticDesign` in `StagePreview`". The program half needs
///   `ProgramModel`, which `StagePreview` does **not** declare (`Package.swift`:
///   `dependencies: ["Interpreter", "EmbroideryEngine"]`). `import ProgramModel` from there
///   compiles today — SwiftPM puts transitive modules on the search path — and that is
///   exactly the problem: it would make ADR-022's declared dependency list a lie that
///   `StagePreviewTargetIsolationTests` cannot see, since the absence of a dependency is
///   enforced by the manifest rather than by that suite. This target already depends on
///   everything, so nothing has to be widened.
/// - `Samples` is where bundled *programs* live, and a 50 000-stitch hatch is precisely the
///   "test shape" ROADMAP M3 says the bundled samples must not be. Adding a `SampleID` case
///   would also drag in a checked-in JSON resource, two localised strings, and five suites
///   that iterate `SampleLibrary.all` — and `SampleID.rawValue` is an M5 persistence token.
///
/// The two halves exist because the story asks for both a **steady state** and a
/// **production path**: the display list is built directly, so a frame can be measured at an
/// exact count without waiting seventeen seconds for an interpreter to reach it; the program
/// is the real interpreter → `RunBatch` → `StitchDisplayList` path, which is what a device
/// capture of a live run actually exercises.
enum SyntheticDesign {
    // MARK: - The display-list half

    /// `count` stitches laid out as a boustrophedon hatch inside ADR-007's stage, in exactly
    /// `colorRuns` maximal colour runs.
    ///
    /// Built by appending to a real `StitchDisplayList` rather than by constructing one:
    /// `colorRuns` and the bounds are derived state that only `append` maintains, and a
    /// fixture that set them directly would be asserting itself.
    static func displayList(count: Int, colorRuns: Int = 1) -> StitchDisplayList {
        var list = StitchDisplayList()
        list.append(contentsOf: stitches(count: count, colorRuns: colorRuns))
        return list
    }

    /// The same stitches, as a plain array — **built without `StitchDisplayList.append`**.
    ///
    /// That exclusion is what makes `StitchDisplayListThroughputTests` a guard rather than a
    /// hang. Measured: with the fixture built *through* `append`, a deliberately quadratic
    /// mutation made the fixture construction quadratic too, outside any measured region and
    /// outside `fastest(within:)`'s budget — so the suite ran for over four hundred seconds
    /// without reaching a single assertion. A guard whose input is produced by the code under
    /// test cannot fail quickly, and on the pre-commit gate cannot fail usefully at all.
    static func stitches(count: Int, colorRuns: Int = 1) -> [PreviewStitch] {
        guard count > 0 else { return [] }

        var stitches: [PreviewStitch] = []
        stitches.reserveCapacity(count)
        let runs = max(1, min(colorRuns, count))
        let rows = max(1, Int((Double(count) / Double(stitchesPerRow)).rounded(.up)))

        var index = 0
        for row in 0 ..< rows where index < count {
            let y = rows == 1 ? 0 : -halfHeight + height * Double(row) / Double(rows - 1)
            for column in 0 ..< stitchesPerRow where index < count {
                // Alternating direction, so consecutive stitches are always neighbours and
                // the plan's segments are the short ones a real design produces. A fixture
                // that flew back to the row start every row would put one enormous traversal
                // per row into the stroke set and measure a different shape of work.
                let position = row.isMultiple(of: 2) ? column : stitchesPerRow - 1 - column
                let x = -halfWidth + width * Double(position) / Double(stitchesPerRow - 1)
                stitches.append(PreviewStitch(
                    position: StagePoint(x: x, y: y),
                    // Equal-sized contiguous buckets: `runs <= count` makes every bucket
                    // non-empty, so the run count is exactly `runs`.
                    color: threadColor(forRun: index * runs / count)
                ))
                index += 1
            }
        }
        return stitches
    }

    /// A colour that always differs from its neighbours.
    ///
    /// Adjacent *runs* sharing a colour would merge in `StitchDisplayList.append`, silently
    /// halving the independent variable of `StitchDrawPlanScalingTests`. Stepping the red
    /// channel guarantees they differ, and the carry into green keeps that true across the
    /// 256-boundary — the one place a naive `index % 256` would repeat.
    private static func threadColor(forRun index: Int) -> ThreadColor {
        ThreadColor(
            red: UInt8(index % 256),
            green: UInt8((index / 256) % 256),
            blue: 128
        )
    }

    private static let stitchesPerRow = 200
    private static let width: Double = 401
    private static let height: Double = 375
    private static var halfWidth: Double { width / 2 }
    private static var halfHeight: Double { height / 2 }

    // MARK: - The program half

    /// The exact number of stitch events `program()` emits.
    ///
    /// Pinned as a literal, the way the bundled samples' figures are — but pinned *here* as
    /// well as in `Samples`, and the duplication is deliberate. The package constant states
    /// what the builder produces; this suite's assertions state what the story needs. If a
    /// later change moved one, the two would disagree and name the drift instead of moving
    /// the goalposts and the measurement together.
    static let programStitchCount = 50_001

    /// The same hatch, walked by the interpreter.
    ///
    /// **Delegated to `Samples`, not reimplemented here.** The app has to link this program —
    /// the screenshots and the device capture are of the real screen — and a test target is
    /// not linkable from an app. A second copy in this file would be the copy the guards in
    /// `SyntheticDesignTests` actually check, while the app ran a different one: every test
    /// green, and a 3 000-stitch capture.
    static func program() -> Program {
        makeUS309SyntheticProgram()
    }
}
