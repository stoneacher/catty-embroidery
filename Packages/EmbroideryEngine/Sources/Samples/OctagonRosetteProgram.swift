import ProgramModel

// Sample 1 — Catrobat Catroid's `DefaultExampleProject`, transcribed brick for
// brick. AGPL-3.0; see Resources/PROVENANCE.md for the attribution, the
// statement-by-statement table, and the divergences.
//
// Verbatim is the point, so **do not "improve" any literal in this file.** The
// side length, the zigzag length and width, and the two loop counts are the
// reference's, and two of this design's properties depend on them in ways that
// are easy to break by accident:
//
//   * The design reaches 246.42 stage points, i.e. it clears ADR-007's ±250
//     stage bound by 3.58 points — 0.72 mm. Widening the zigzag or lengthening
//     the side puts a bundled sample off the hoop.
//   * All 64 sides sit exactly on a `floor(distance / length)` boundary
//     (100 / 2 = 50), and nine of them fall an ulp short, which is why this
//     design emits 3194 stitches and not 3201. That is pinned and explained by
//     `SampleThresholdTests.theRosetteDependsOnLibmRoundingOfHypot`.

/// Catroid's two loop-count variables. The names are Catroid's own English
/// string resources (`default_project_inner_loop` / `default_project_outer_loop`,
/// `values/strings.xml:1373-1375`).
///
/// Catroid *localizes* these — a Russian user's default project has variables
/// named `Внутренний Цикл` and `Внешний цикл` — so pinning the English literals
/// is a deliberate divergence: a variable name is an identifier in our JSON
/// format (ADR-003), and a program whose identifiers change with the device
/// locale would not round-trip.
private let innerLoopVariable = "Inner Loop"
private let outerLoopVariable = "Outer Loop"

func makeOctagonRosetteProgram() -> Program {
    let bricks: [Brick] = [
        // script.addBrick(new SetVariableBrick(new Formula(8), variableInnerLoop));
        .setVariable(name: innerLoopVariable, to: .number(8)),
        // script.addBrick(new SetVariableBrick(new Formula(8), variableOuterLoop));
        .setVariable(name: outerLoopVariable, to: .number(8)),
        // script.addBrick(new ZigZagStitchBrick(new Formula(2), new Formula(10)));
        .zigZagStitch(length: .number(2), width: .number(10)),

        // RepeatBrick(repeatUntilFormulaOuterLoop). Catroid seeds the formula
        // with `new Formula(1)` and then calls setRoot(USER_VARIABLE …), which
        // discards the literal — so the repeat count is a bare variable
        // reference, not "1" and not a formula containing 1.
        .repeatLoop(times: .variable(outerLoopVariable)),

        // innerLoopRepeat = RepeatBrick(repeatUntilFormulaInnerLoop)
        .repeatLoop(times: .variable(innerLoopVariable)),
        // innerLoopRepeat.addBrick(new MoveNStepsBrick(new Formula(100)));
        .moveNSteps(.number(100)),
        // innerLoopRepeat.addBrick(new TurnRightBrick(360 / innerLoop));
        .turnRight(.binary(.divide, .number(360), .variable(innerLoopVariable))),
        .loopEnd,

        // outerLoopRepeat.addBrick(new TurnRightBrick(360 / outerLoop));
        // Added to the *outer* loop after the inner one, so it runs once per
        // octagon and rotates the next octagon about the shared start corner.
        .turnRight(.binary(.divide, .number(360), .variable(outerLoopVariable))),
        .loopEnd
    ]

    return Program(
        name: "Octagon Rosette",
        scenes: [
            Scene(
                name: "Scene 1",
                objects: [
                    Object(
                        name: "Needle", // R.string.default_project_needle_name
                        startX: 0,
                        startY: 0,
                        // ADR-007's 0 degrees = up, and this *is* Catroid's
                        // default rather than an adaptation of it: MoveNStepsAction
                        // reads Look.realRotation, which Look.java:89 initialises
                        // from the libGDX rotation (0). DEGREE_UI_OFFSET = 90 only
                        // enters setMotionDirectionInUserInterfaceDimensionUnit,
                        // which this project never calls.
                        startHeading: 0,
                        zIndex: 0,
                        // needle.addUserVariable(inner); needle.addUserVariable(outer);
                        // — Sprite.addUserVariable, i.e. object-scoped, inner
                        // declared first. Both start at 0 and are assigned 8 by
                        // the two setVariable bricks before either loop reads them.
                        variables: [
                            Variable(name: innerLoopVariable),
                            Variable(name: outerLoopVariable)
                        ],
                        scripts: [Script(header: .whenStarted, bricks: bricks)]
                    )
                ]
            )
        ]
    )
}
