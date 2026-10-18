import ProgramModel

// Sample 3 — our own content (Brick backend, slice 7). It exists to show what
// the brick backend added, so it uses each piece where it does real work:
//
// - **Arc** draws the twelve petals, each a full circle in eight 45° arcs.
// - **`sin`** sets each circle's radius, 40 + 15·sin(petal·120°), so the petals
//   swell and shrink in a wave around the flower rather than being twelve copies.
// - **Absolute headings** start every circle: the needle returns to the centre
//   and points to petal·30°. Each Arc leaves the needle facing along its last
//   chord, a little behind the tangent (ADR-047, mirrored from Catroid), and
//   turning *relative* to that would let the error pile up into a lopsided fan.
// - **GoThrough** draws the stem, curving down from the centre in a second
//   colour, its bend measured from the needle's own x position (a **sensor**).

/// Which petal is being drawn, 0 to 11.
private let petalVariable = "Petal"

/// Stitch spacing, in stage points. **Must stay an integer**: the interpreter
/// reads `runningStitch`'s length with `interpretInteger` (ADR-017).
private let stitchLength: Double = 4

/// Rose, then leaf green. They must differ as parsed `ThreadColor`s or ADR-015
/// makes the second set a silent no-op and the design ships one colour block.
private let petalThread = "#db2777"
private let stemThread = "#16a34a"

func makeArcFlowerProgram() -> Program {
    let petal = Formula.variable(petalVariable)
    // 40 + 15·sin(petal·120°): radii 40, 53, 27, repeating four times around the
    // flower, so it has four-fold symmetry. `petal·60°` ran two waves over the
    // twelve petals and drew a two-lobed propeller (seen on the stage, slice 7).
    let radius = Formula.binary(
        .plus,
        .number(40),
        .binary(.mult, .number(15), .unaryFunction(.sin, .binary(.mult, petal, .number(120))))
    )
    let bricks: [Brick] = [
        // Silent under ADR-015: nothing has been stitched yet.
        .setThreadColor(hex: petalThread),
        .runningStitch(length: .number(stitchLength)),
        .setVariable(name: petalVariable, to: .number(0)),
        .repeatLoop(times: .number(12)),
        .placeAt(x: .number(0), y: .number(0)),
        .pointInDirection(.binary(.mult, petal, .number(30))),
        // Eight 45° arcs rather than one 360°: an Arc costs one tick however far
        // it goes (ADR-047), so a whole circle would appear in a single frame and
        // the flower would finish in ~50 ticks, under the library's two-second
        // floor. Eighths make it grow visibly, petal by petal.
        .repeatLoop(times: .number(8)),
        .arc(direction: .left, radius: radius, degrees: .number(45)),
        .loopEnd,
        .changeVariableBy(name: petalVariable, value: .number(1)),
        .loopEnd,
        .setThreadColor(hex: stemThread),
        .placeAt(x: .number(0), y: .number(0)),
        // Through a point 45 to the right of wherever the needle is, down to the
        // bottom of the hoop.
        .goThrough(
            throughX: .binary(.plus, .sensor(.objectX), .number(45)),
            throughY: .number(-120),
            x: .number(0),
            y: .number(-210)
        ),
        // Tie off (ADR-012's five-point tack).
        .sewUp
    ]

    return Program(
        name: "Arc Flower",
        scenes: [
            Scene(
                name: "Scene 1",
                objects: [
                    Object(
                        name: "Needle",
                        startX: 0,
                        startY: 0,
                        startHeading: 0, // ADR-007: 0 degrees = up
                        zIndex: 0,
                        variables: [Variable(name: petalVariable)],
                        scripts: [Script(header: .whenStarted, bricks: bricks)]
                    )
                ]
            )
        ]
    )
}
