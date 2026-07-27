import EmbroideryEngine
import Interpreter
import ProgramModel

// The differential half of US-207's golden, split out of `GoldenProgramOracle`
// so that file stays what its header claims: machinery shared by every golden
// program. The independent half lives in `GoldenSquareLiterals`.

// MARK: - US-207: the square

/// US-207's square: side 20 stage units at stitch length 5 — exactly four stitch
/// intervals per side, so every interpolant lands on a whole stage unit — sewn in
/// green, tied off, finalized as "square".
enum GoldenSquare {
    static let length = 5.0
    static let hex = "#00ff00"
    static let designName = "square"
    static let color = ThreadColor(red: 0, green: 255, blue: 0)
    static let actor = ActorID(0)
    static let layer = 0

    static let spec = PolygonSpec(
        sides: 4,
        side: 20,
        turn: 90,
        patternBrick: .runningStitch(length: .number(length)),
        hex: hex,
        designName: designName
    )

    /// The program as the golden runs it: object at the stage origin, heading 0.
    static var program: Program {
        polygonProgram(spec)
    }

    /// The same square sewn by an object with a non-default start state. Used to
    /// pin the `Object` → `ObjectRuntime` seam (`startX`/`startY`/`startHeading` →
    /// `VirtualNeedle`, `zIndex` → layer) and the claim that a pattern activates at
    /// the *current* needle position: none of that is observable from a program
    /// that begins at the origin facing up on layer 0 (swift-code-reviewer US-207
    /// proved `startHeading` had no killing test anywhere in the package).
    static let displacedStart = StagePoint(x: -20, y: -20)
    static let displacedHeading = 90.0
    static let displacedLayer = 3

    static var displacedProgram: Program {
        var program = polygonProgram(spec)
        program.scenes[0].objects[0].startX = displacedStart.x
        program.scenes[0].objects[0].startY = displacedStart.y
        program.scenes[0].objects[0].startHeading = displacedHeading
        program.scenes[0].objects[0].zIndex = displacedLayer
        return program
    }

    /// Recomputed per access (a `static var`, not a `let`): parallel Swift Testing
    /// runs must not share the replay's mutable pattern state.
    static var oracle: GoldenReplay {
        let pattern = RunningStitchPattern(length: length, start: StagePoint(x: 0, y: 0))
        return replayGoldenProgram(polygonOps(spec, pattern: pattern), actor: actor, layer: layer)
    }

    /// The square sewn by the **second** object of a scene, the first being inert.
    /// `ActorID` is the global object index (ADR-018), so every event must carry
    /// `ActorID(1)` while the assembled stream is unchanged — the discriminator for
    /// an interpreter that hardcodes actor 0 into its events (Codex US-207 round 2).
    static let secondActor = ActorID(1)

    /// `inSeparateScene: false` puts the inert object and the stitcher in one
    /// scene; `true` gives each its own scene. ADR-018 makes `ActorID` the
    /// **global** object index in scene→object order, so both must yield
    /// `ActorID(1)` — a regression resetting the counter per scene would only show
    /// up in the two-scene case, and no interpreter test used a multi-scene program
    /// before (Codex US-207 round 3).
    static func secondObjectProgram(inSeparateScene: Bool) -> Program {
        let stitcher = polygonProgram(spec).scenes[0].objects[0]
        let inert = Object(name: "inert")
        return inSeparateScene
            ? Program(scenes: [Scene(objects: [inert]), Scene(objects: [stitcher])])
            : Program(scenes: [Scene(objects: [inert, stitcher])])
    }

    static var secondObjectOracle: GoldenReplay {
        let pattern = RunningStitchPattern(length: length, start: StagePoint(x: 0, y: 0))
        return replayGoldenProgram(polygonOps(spec, pattern: pattern), actor: secondActor, layer: layer)
    }

    static var displacedOracle: GoldenReplay {
        let pattern = RunningStitchPattern(length: length, start: displacedStart)
        return replayGoldenProgram(
            polygonOps(spec, pattern: pattern),
            start: displacedStart,
            heading: displacedHeading,
            actor: actor,
            layer: displacedLayer
        )
    }
}
