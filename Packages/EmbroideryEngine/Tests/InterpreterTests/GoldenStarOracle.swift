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
///   colour change.
///
///   It is *not* a safe choice, and the earlier version of this comment claiming
///   it "avoids the cliff" was wrong (swift-code-reviewer US-208). A pentagram's
///   move directions are irrational, so a side whose nominal length is a whole
///   multiple of `length` sits exactly **on** the interval boundary and the last
///   bit of `hypot` decides the emission structure. Side 4's exact distance from
///   the anchor is 19.999999999999998122…, i.e. 1.878e-15 short of 20 — past the
///   half-ulp boundary by a mere 1e-16. Darwin's `hypot` is 0.53 ulp high here
///   and returns 20.0, giving 4 intervals; the correctly rounded result is
///   19.999999999999996, which gives 3 and deforms the design from side 4 on.
///   `hypot` is not required to be correctly rounded by C or IEEE-754, and
///   implementations disagree here — Python 3.14.6 on the same machine returns
///   the correctly rounded value. **This golden is therefore pinned to Apple
///   platforms' libm**, which today is the package's only deployment target and
///   its only CI, but is a latent trap for a Linux SwiftPM job.
///
///   No integer `side / length` ratio escapes this — the boundary is where the
///   ratio puts it. A ratio with real margin would decouple the anchor from the
///   vertices and make the hand derivation far harder, which is the trade-off
///   not taken here. `theGoldenDependsOnLibmRoundingOfHypot` measures the
///   distances directly, so a platform or toolchain move names its own cause
///   rather than leaving a dozen unexplained golden diffs.
/// - **`length: 5` ≠ `width: 4`.** Equal values would make a length/width
///   transposition in the `zigZagStitch` dispatch unobservable — see
///   `PolygonSpec.patternBrick`. Both are `Float`-exact, so nothing is lost on
///   the way through the dispatch's `interpretFloat`. That is a precondition of
///   this golden, not coverage of that seam: with integral values the
///   `interpretFloat` and `interpretInteger` paths are indistinguishable here,
///   and US-206's `zigZagStitch length AND width come through interpretFloat`
///   is what actually pins it (swift-code-reviewer US-208, mutation-proven).
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
    static let firstHex = "#ff0000"
    static let secondHex = "#0000ff"
    static let firstColor = ThreadColor(red: 255, green: 0, blue: 0)
    static let secondColor = ThreadColor(red: 0, green: 0, blue: 255)
    static let sidesBeforeColorChange = 2
    static let designName = "star"
    static let actor = ActorID(0)
    static let layer = 0

    static let spec = PolygonSpec(
        sides: sides,
        side: side,
        turn: turn,
        patternBrick: .zigZagStitch(length: .number(length), width: .number(width)),
        hex: firstHex,
        designName: designName,
        midColor: MidProgramColor(hex: secondHex, afterSides: sidesBeforeColorChange)
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
