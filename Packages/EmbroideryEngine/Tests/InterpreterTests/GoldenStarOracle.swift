import EmbroideryEngine
import Interpreter
import ProgramModel

// The differential half of US-208's golden, the counterpart of
// `GoldenSquareOracle`. The independent half lives in `GoldenStarLiterals` and
// is deliberately kept out of this file — see that file's header.

// MARK: - US-208: the star

/// US-208's five-pointed star: five 20-unit sides turning 144° each, sewn in
/// zigzag, with a second thread colour taken up after two sides.
///
/// The parameters are load-bearing, not cosmetic:
///
/// - **`side: 20`, `length: 5` — the square's, deliberately.** Holding them
///   fixed isolates what US-208 actually adds: the turn, the pattern and the
///   colour change. It is also not a free choice. A star's move directions are
///   irrational, so `hypot` need not return the nominal side, and the pattern
///   measures from its previous *clamped* anchor rather than from the needle's
///   previous position — an ulp short of a whole multiple of `length` costs the
///   side an entire interval and leaves the anchor a length behind, compounding
///   over the rest of the walk. Plenty of plausible pairs land there (side 30 at
///   length 5 yields `[6, 6, 6, 5, 5]`); 20 at 5 gives a clean `[4, 4, 4, 4, 4]`.
///   `starParametersAvoidTheIntervalCliff` pins both halves of that.
/// - **`length: 5` ≠ `width: 4`.** Equal values would make a length/width
///   transposition in the `zigZagStitch` dispatch unobservable — see
///   `PolygonSpec.patternBrick`. Both are `Float`-exact, which matters because
///   the dispatch reads them through `interpretFloat` before widening.
/// - **Two sides before the colour change.** Enough that stitches exist when the
///   set happens, so ADR-015 arms a change instead of silently choosing the
///   starting colour, as it does for the leading set.
enum GoldenStar {
    static let sides = 5
    static let side = 20.0
    static let turn = 144.0
    static let length = 5.0
    static let width = 4.0
    /// Catroid's `BrickValues.THREAD_COLOR` default, then a differing blue.
    static let startHex = "#ff0000"
    static let midHex = "#0000ff"
    static let startColor = ThreadColor(red: 255, green: 0, blue: 0)
    static let midThreadColor = ThreadColor(red: 0, green: 0, blue: 255)
    static let sidesBeforeColorChange = 2
    static let designName = "star"
    static let actor = ActorID(0)
    static let layer = 0

    static let spec = PolygonSpec(
        sides: sides,
        side: side,
        turn: turn,
        patternBrick: .zigZagStitch(length: .number(length), width: .number(width)),
        hex: startHex,
        designName: designName,
        midColor: MidProgramColor(hex: midHex, afterSides: sidesBeforeColorChange)
    )

    static var program: Program {
        polygonProgram(spec)
    }

    /// Recomputed per access (a `static var`, not a `let`): parallel Swift Testing
    /// runs must not share the replay's mutable pattern state — and the zigzag
    /// carries more of it than the running stitch, since its alternation sign
    /// persists across every update.
    static var oracle: GoldenReplay {
        let pattern = ZigzagStitchPattern(length: length, width: width, start: StagePoint(x: 0, y: 0))
        return replayGoldenProgram(polygonOps(spec, pattern: pattern), actor: actor, layer: layer)
    }
}
