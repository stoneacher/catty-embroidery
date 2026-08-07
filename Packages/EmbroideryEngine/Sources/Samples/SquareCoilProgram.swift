import ProgramModel

// Sample 2 — our own content, no reference origin. Catroid ships exactly one
// starter project and no sample files, so there is nothing to port here.
//
// A square spiral: each side is longer than the last, so the walk winds outward
// in a nested square coil. It is deliberately unlike sample 1 in three ways —
// silhouette (a coil, not a circular rosette), stitch type (triple, not zigzag),
// and thread count (two colours, not one) — because two bundled samples that
// look like each other teach a first-time user nothing about what the app can do.
//
// It is also the only sample that drives motion from a *variable*: sample 1 uses
// variables solely as loop counts, so without this one nothing in the bundled
// content exercises `changeVariableBy` or a variable-valued `moveNSteps`.

/// The growing side length, in stage points.
private let sideVariable = "Side"

/// Stitch spacing, in stage points. **Must stay an integer**: the interpreter
/// reads `tripleStitch`'s length with `interpretInteger` (Catroid's
/// `interpretInteger` contract, ADR-017), so 6.5 would silently become 6.
private let stitchLength: Double = 6

/// First side, and the amount each side grows by.
///
/// These three numbers are chosen together for ADR-019, and the choice is the
/// point: `9 ≡ 3 (mod 6)` and the growth is a whole multiple of 6, so **every**
/// side length is congruent to 3 modulo the stitch length — exactly halfway
/// between two `floor(distance / length)` boundaries, which is the largest
/// margin the parameter space allows.
///
/// Sample 1 cannot have this (its ratio is Catroid's, and it is exactly integral,
/// so it sits *on* the boundary); this sample is where ADR-019's "handle it by
/// choosing inputs off the boundary" clause is actually exercised. Measured
/// closest approach: over 10^13 ulps. Changing any of the three forfeits that.
private let firstSide: Double = 9
private let sideGrowth: Double = 6

/// Sides walked before the colour change, and after it.
///
/// 31/13 rather than a symmetric 22/22, because the two DST colour blocks should
/// hold roughly equal amounts of *thread*, not equal numbers of sides. Cumulative
/// thread after `k` sides grows as `3k(k+1)/2`, so the halfway point of 44 sides
/// is 31 — which splits the design 1489 / 1487 stitches instead of 760 / 2216.
/// A balanced split also makes the colour-change assertion mean something: "a
/// change exists somewhere" would pass against a change on the second stitch.
private let sidesBeforeColorChange = 31
private let sidesAfterColorChange = 13

/// Deep blue, then amber. They must differ as parsed `ThreadColor`s or ADR-015
/// makes the second set a silent no-op and the design ships one colour block.
private let firstThread = "#1d4ed8"
private let secondThread = "#f59e0b"

func makeSquareCoilProgram() -> Program {
    var bricks: [Brick] = [
        // Silent under ADR-015 — nothing has been stitched yet, so this selects
        // the first block's colour and arms no change record.
        .setThreadColor(hex: firstThread),
        .tripleStitch(length: .number(stitchLength)),
        .setVariable(name: sideVariable, to: .number(firstSide))
    ]

    bricks += coilLoop(sides: sidesBeforeColorChange)
    // Between the two loops, not inside one: this is the only arrangement that
    // executes the brick exactly once and partitions the stream unambiguously by
    // colour (the US-208 shape). Inside the loop it would re-set the same colour
    // 13 times — an ADR-015 no-op each time, so the header would still read CO 2,
    // but at the cost of 13 ticks and an unclear partition.
    bricks.append(.setThreadColor(hex: secondThread))
    bricks += coilLoop(sides: sidesAfterColorChange)

    // Tie off. Five points at ±3 stage units along the closing heading (ADR-012's
    // five-point tack, not Catty's four-point).
    bricks.append(.sewUp)

    return Program(
        name: "Square Coil",
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
                        variables: [Variable(name: sideVariable)],
                        scripts: [Script(header: .whenStarted, bricks: bricks)]
                    )
                ]
            )
        ]
    )
}

/// One `repeatLoop`/`loopEnd` pair walking `sides` edges of the coil.
///
/// Three action bricks per side, so each side costs three ticks — which is what
/// carries this 44-side design past the story's 120-tick floor without padding it
/// with `wait` bricks. (A `wait` would satisfy "animates for at least two seconds"
/// on paper and betray it on screen: the preview would simply freeze.)
private func coilLoop(sides: Int) -> [Brick] {
    [
        .repeatLoop(times: .number(Double(sides))),
        .moveNSteps(.variable(sideVariable)),
        .turnRight(.number(90)),
        .changeVariableBy(name: sideVariable, value: .number(sideGrowth)),
        .loopEnd
    ]
}
