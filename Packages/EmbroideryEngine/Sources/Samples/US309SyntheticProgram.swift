#if DEBUG
import ProgramModel

// US-309's measurement fixture: a 50 000-stitch design, as a program the interpreter walks.
//
// **In `Samples` because the app must be able to link it**, and in `Samples` rather than
// anywhere else because it needs `ProgramModel` and nothing else — so it costs ADR-016's
// dependency arrow nothing. It is emphatically **not** in `SampleLibrary.all`: ROADMAP M3
// requires the bundled samples to be visually appealing designs "not test shapes", and this
// is a hatch whose only virtue is that it has fifty thousand stitches.
//
// `#if DEBUG` so a Release build a user could install contains neither the builder nor the
// `SampleID` case that reaches it. The measurement build is a Release build with `DEBUG`
// defined on the command line — command-line build settings are global overrides, so the
// definition reaches package targets too, which is what makes one flag enough (ADR-029).

/// The design's width, in stage points, and the spacing between rows.
///
/// **Every constant here is half a stitch length off a `floor(distance / length)` boundary,
/// and that is what makes the stitch count reproducible** (ADR-019). A row of 401 points at a
/// stitch length of 2 is 200.5 lengths, so neither the trig error a 90° turn introduces nor
/// the sub-length surplus the running stitch carries into the next row can move the floor.
/// The obvious parameters — a row that is a whole number of stitch lengths — sit *on* the
/// boundary, where one ulp costs a stitch per row and 250 stitches per design.
private let rowWidth: Double = 401

/// Deliberately **shorter than the stitch length**, so the move between rows emits nothing at
/// all and leaves the running stitch's anchor where the row ended. That is what keeps every
/// row worth exactly 200 stitches instead of 200 plus a spacing stitch whose position depends
/// on the previous row's remainder.
private let rowSpacing: Double = 1.5

/// Integral on purpose: the brick reads its length through `interpretInteger` (ADR-017), so a
/// fractional length is truncated — and at 0.5 it truncates to zero, which
/// `RunningStitchPattern` treats as degenerate and emits **five** stitches for the whole
/// design. Measured, during planning, on a design that otherwise looked correct.
private let stitchLength: Double = 2

/// 125 iterations × 2 rows × 200 stitches = 50 000, plus the running stitch's anchor.
private let rowPairs = 125

/// The exact number of stitch events this program emits.
///
/// Pinned as a literal the way the bundled samples' figures are: a bound alone lets the count
/// drift within it and takes the measurement's premise along with it.
public let us309SyntheticStitchCount = 50_001

/// A boustrophedon hatch that fills ADR-007's stage and stitches 50 001 times over roughly
/// seventeen seconds at ADR-018's one tick per displayed frame.
public func makeUS309SyntheticProgram() -> Program {
    var bricks: [Brick] = [
        .runningStitch(length: .number(stitchLength)),
        .repeatLoop(times: .number(Double(rowPairs)))
    ]
    // One iteration is two rows and two spacing moves, so the loop leaves the needle facing
    // the way it started and the hatch stays a hatch rather than drifting into a spiral.
    bricks += [
        .moveNSteps(.number(rowWidth)),
        .turnLeft(.number(90)),
        .moveNSteps(.number(rowSpacing)),
        .turnLeft(.number(90)),
        .moveNSteps(.number(rowWidth)),
        .turnRight(.number(90)),
        .moveNSteps(.number(rowSpacing)),
        .turnRight(.number(90))
    ]
    bricks.append(.loopEnd)

    return Program(
        name: "US309 Synthetic",
        scenes: [Scene(objects: [Object(
            name: "Needle",
            startX: -rowWidth / 2,
            startY: -Double(rowPairs) * rowSpacing,
            // ADR-007: 0 degrees is up, so 90 faces the first row along +x.
            startHeading: 90,
            zIndex: 0,
            scripts: [Script(header: .whenStarted, bricks: bricks)]
        )])]
    )
}
#endif
