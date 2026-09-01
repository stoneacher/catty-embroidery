import EmbroideryEngine
import ProgramModel
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
    /// **Pinned as a literal, the way the bundled samples' figures are.** A bound alone lets
    /// the count drift within it and takes the measurement's premise along with it; a pinned
    /// literal makes a drift name itself instead of moving both sides of an equation at once.
    static let programStitchCount = 50_001

    /// The same hatch, walked by the interpreter.
    ///
    /// **Every constant below is chosen half a stitch length off a `floor(distance / length)`
    /// boundary (ADR-019), and that is what makes the count reproducible.** A row of 401
    /// stage points at a stitch length of 2 is 200.5 lengths, so the trig error a 90° turn
    /// introduces — and the sub-length surplus the running stitch carries from the previous
    /// row — can move the quotient by a large multiple of an ulp without moving the floor.
    /// The obvious parameters (a row that is a whole number of stitch lengths) sit *on* the
    /// boundary, where an error of one ulp costs a stitch per row and 250 stitches per run.
    ///
    /// The row spacing is deliberately **shorter than the stitch length**, so the move
    /// between rows emits nothing at all and leaves the running stitch's anchor where the row
    /// ended. That is what keeps every row worth exactly 200 stitches rather than 200 plus a
    /// spacing stitch whose position depends on the previous row's remainder.
    ///
    /// `.runningStitch(length: 2)` and not `1.5`: the brick reads its length through
    /// `interpretInteger` (ADR-017), so a fractional length is truncated — and at 0.5 it
    /// truncates to zero, which `RunningStitchPattern` treats as degenerate and emits
    /// **five** stitches for the whole design.
    static func program() -> Program {
        var bricks: [Brick] = [
            .runningStitch(length: .number(stitchLength)),
            .repeatLoop(times: .number(Double(rowPairs)))
        ]
        // One iteration is two rows and one full spacing pair, so the loop leaves the needle
        // facing the way it started and the hatch stays a hatch.
        bricks += [
            .moveNSteps(.number(width)),
            .turnLeft(.number(90)),
            .moveNSteps(.number(rowSpacing)),
            .turnLeft(.number(90)),
            .moveNSteps(.number(width)),
            .turnRight(.number(90)),
            .moveNSteps(.number(rowSpacing)),
            .turnRight(.number(90))
        ]
        bricks.append(.loopEnd)

        return Program(
            name: "US-309 Synthetic",
            scenes: [Scene(objects: [Object(
                name: "Needle",
                startX: -halfWidth,
                startY: -halfHeight,
                // ADR-007: 0 degrees is up, so 90 faces the first row along +x.
                startHeading: 90,
                zIndex: 0,
                scripts: [Script(header: .whenStarted, bricks: bricks)]
            )])]
        )
    }

    /// 2, and integral on purpose — see `program()`.
    private static let stitchLength: Double = 2
    /// Shorter than `stitchLength`, so the inter-row move emits nothing.
    private static let rowSpacing: Double = 1.5
    /// 125 iterations × 2 rows × 200 stitches = 50 000, plus the running stitch's anchor.
    private static let rowPairs = 125
}
