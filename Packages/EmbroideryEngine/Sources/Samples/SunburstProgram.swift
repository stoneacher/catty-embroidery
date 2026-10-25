import ProgramModel

// Sample 4 — our own content (Variables, slice 8). It exists to show what the
// Variables feature added, so each piece does real work:
//
// - **For values from 1 to 36 in Ray** counts the rays, and the counter places
//   each one: its tip at Ray·10° − 5°, the valley after it at Ray·10°, both by
//   `sin`/`cos` from the centre. Every point is absolute, so nothing drifts
//   around the circle.
// - **If Long = 1 … else …** makes the rays long and short in turn. Each branch
//   flips `Long` for the next ray. The condition is one comparison of a variable
//   and a number, so it opens in the comparison editor rather than locked.
// - A **circle in a second colour** sits inside the valleys, drawn with Arcs.
//
// The rays are one zigzag outline, tip to valley to tip, never back to the
// centre. A first version drew each ray out from the centre and back: the way
// back then measured exactly a whole number of stitches from the last stitch
// (148 = 37 · 4), a few ulps from ADR-019's floor boundary, on every ray. The
// screening found it before any test was pinned (journal, 2026-10-25).

/// The For loop's counter, 1 to 36.
private let rayVariable = "Ray"

/// 1 while the next ray is long, 0 while it is short.
private let longVariable = "Long"

/// Stitch spacing, in stage points. **Must stay an integer**: the interpreter
/// reads `runningStitch`'s length with `interpretInteger` (ADR-017).
private let stitchLength: Double = 4

private let longRay: Double = 150
private let shortRay: Double = 85
/// The valleys between the rays, and where the needle starts: straight up.
private let valleyRadius: Double = 40
private let circleRadius: Double = 35

/// Amber rays, a red circle: both palette swatches (ADR-040, `ThreadPaletteTests`).
/// They must differ as parsed `ThreadColor`s or ADR-015 makes the second set a
/// silent no-op and the design ships one block.
private let rayThread = "#f59e0b"
private let circleThread = "#ff0000"

/// `placeAt` the point `radius` from the centre at `heading` degrees (ADR-007:
/// 0° up, clockwise), so x = r·sin and y = r·cos.
private func placeAt(radius: Double, heading: Formula) -> Brick {
    .placeAt(
        x: .binary(.mult, .number(radius), .unaryFunction(.sin, heading)),
        y: .binary(.mult, .number(radius), .unaryFunction(.cos, heading))
    )
}

func makeSunburstProgram() -> Program {
    let valley = Formula.binary(.mult, .variable(rayVariable), .number(10))
    let tip = Formula.binary(.minus, valley, .number(5))
    let bricks: [Brick] = [
        // Silent under ADR-015: nothing has been stitched yet.
        .setThreadColor(hex: rayThread),
        .runningStitch(length: .number(stitchLength)),
        .setVariable(name: longVariable, to: .number(1)),
        .forVariableFromTo(name: rayVariable, from: .number(1), to: .number(36)),
        .ifElse(condition: .binary(.equal, .variable(longVariable), .number(1))),
        placeAt(radius: longRay, heading: tip),
        .setVariable(name: longVariable, to: .number(0)),
        .elseBranch,
        placeAt(radius: shortRay, heading: tip),
        .setVariable(name: longVariable, to: .number(1)),
        .ifEnd,
        placeAt(radius: valleyRadius, heading: valley),
        .loopEnd,
        // The last valley is the start, straight up. Step in to the circle and
        // face left, so a left turn circles the centre.
        .setThreadColor(hex: circleThread),
        .placeAt(x: .number(0), y: .number(circleRadius)),
        .pointInDirection(.number(-90)),
        // Eighths, as in Arc Flower: an Arc costs one tick however far it goes
        // (ADR-047), so the circle grows visibly rather than in one frame.
        .repeatLoop(times: .number(8)),
        .arc(direction: .left, radius: .number(circleRadius), degrees: .number(45)),
        .loopEnd,
        // Tie off (ADR-012's five-point tack).
        .sewUp
    ]

    return Program(
        name: "Sunburst",
        scenes: [
            Scene(
                name: "Scene 1",
                objects: [
                    Object(
                        name: "Needle",
                        startX: 0,
                        startY: valleyRadius,
                        startHeading: 0, // ADR-007: 0 degrees = up
                        zIndex: 0,
                        variables: [Variable(name: rayVariable), Variable(name: longVariable)],
                        scripts: [Script(header: .whenStarted, bricks: bricks)]
                    )
                ]
            )
        ]
    )
}
