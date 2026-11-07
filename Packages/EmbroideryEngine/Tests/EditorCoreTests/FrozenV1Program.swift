import EditorCore
import ProgramModel

// MARK: - The maximal v1 program

enum FrozenV1 {
    /// Every JSON escape class: slash (`.withoutEscapingSlashes`), quote, backslash, tab, newline,
    /// a control character, a non-BMP scalar and non-ASCII letters (Codex slice round, Medium).
    static let sentinel = "a/b \"q\" \\ \t\n\u{1} 🧵 Größe ✂︎"

    /// A nested formula placed in every formula slot of every brick.
    static let composite: Formula = .binary(
        .plus,
        .unaryFunction(.abs, .variable(sentinel)),
        .unaryMinus(.number(1))
    )

    /// Every formula shape v1 can hold, each leaf vocabulary through its test-owned tags.
    /// Payloads are deliberately varied (negative zero, a subnormal, the largest finite value,
    /// the sentinel name) so the frozen bytes also pin how numbers and strings are written.
    static let formulas: [Formula] = [
        .number(0),
        .number(0.1),
        .number(-0.0),
        .number(.leastNonzeroMagnitude),
        .number(.greatestFiniteMagnitude),
        .number(-12),
        .variable(sentinel),
        .unaryMinus(.variable("i")),
        .logicalNot(.constant(.false)),
        composite
    ]
        + V1Operator.allCases.map { .binary($0.value, .number(2), .variable("v")) }
        + V1UnaryFunction.allCases.map { .unaryFunction($0.value, .number(0.5)) }
        + V1BinaryFunction.allCases.map { .binaryFunction($0.value, .number(7), .sensor(.objectY)) }
        + V1Constant.allCases.map { .constant($0.value) }
        + V1Sensor.allCases.map { .sensor($0.value) }

    /// Every brick case with simple payloads, each opener closed so the document admits it.
    static let simpleBricks: [Brick] = [
        .moveNSteps(.number(10)),
        .turnLeft(.number(15)),
        .turnRight(.number(-15)),
        .pointInDirection(.number(90)),
        .placeAt(x: .number(-100), y: .number(100.5)),
        .setX(.number(1)),
        .setY(.number(2)),
        .changeXBy(.number(3)),
        .changeYBy(.number(4)),
        .arc(direction: .left, radius: .number(30), degrees: .number(90)),
        .arc(direction: .right, radius: .number(20), degrees: .number(180)),
        .goThrough(throughX: .number(5), throughY: .number(6), x: .number(7), y: .number(8)),
        .repeatLoop(times: .number(3)),
        .forever,
        .loopEnd,
        .loopEnd,
        .repeatUntil(condition: .binary(.greaterThan, .variable("v"), .number(5))),
        .forVariableFromTo(name: "i", from: .number(1), to: .number(4)),
        .loopEnd,
        .loopEnd,
        .wait(seconds: .number(0.25)),
        .waitUntil(condition: .constant(.true)),
        .ifThen(condition: .constant(.true)),
        .ifElse(condition: .constant(.false)),
        .elseBranch,
        .ifEnd,
        .ifEnd,
        .changeVariableBy(name: "v", value: .number(-1)),
        .stitch,
        .setThreadColor(hex: "#1A2b3C"),
        .runningStitch(length: .number(2)),
        .zigZagStitch(length: .number(2), width: .number(3)),
        .tripleStitch(length: .number(2.5)),
        .sewUp,
        .stopRunningStitch,
        .writeEmbroideryToFile(name: "Blüte ⚘.dst")
    ]

    /// Every formula-bearing brick again, with the composite in every slot and the sentinel in
    /// every string payload.
    static let compositeBricks: [Brick] = [
        .moveNSteps(composite),
        .turnLeft(composite),
        .turnRight(composite),
        .pointInDirection(composite),
        .placeAt(x: composite, y: composite),
        .setX(composite),
        .setY(composite),
        .changeXBy(composite),
        .changeYBy(composite),
        .arc(direction: .left, radius: composite, degrees: composite),
        .goThrough(throughX: composite, throughY: composite, x: composite, y: composite),
        .repeatLoop(times: composite),
        .loopEnd,
        .repeatUntil(condition: composite),
        .loopEnd,
        .forVariableFromTo(name: sentinel, from: composite, to: composite),
        .loopEnd,
        .wait(seconds: composite),
        .waitUntil(condition: composite),
        .ifThen(condition: composite),
        .ifEnd,
        .ifElse(condition: composite),
        .elseBranch,
        .ifEnd,
        .setVariable(name: sentinel, to: composite),
        .changeVariableBy(name: sentinel, value: composite),
        .runningStitch(length: composite),
        .zigZagStitch(length: composite, width: composite),
        .tripleStitch(length: composite),
        .writeEmbroideryToFile(name: sentinel)
    ]

    /// The palette's default payloads as they were when v1 froze (2026-11-07), copied as literals
    /// from `BrickDefaults` and `BrickKind.template()` rather than read from them. A custom coding
    /// that omitted a field only when it equals its default would otherwise pass: the
    /// palette-created `"embroidery.dst"` and the empty variable name were in no other brick (Codex
    /// handover round 1, High). Literals, so a later change of a palette default isn't mistaken for
    /// a format change.
    static let templateBricksAtFreeze: [Brick] = [
        .moveNSteps(.number(10)),
        .turnLeft(.number(15)),
        .turnRight(.number(15)),
        .pointInDirection(.number(90)),
        .placeAt(x: .number(100), y: .number(200)),
        .setX(.number(100)),
        .setY(.number(200)),
        .changeXBy(.number(10)),
        .changeYBy(.number(10)),
        .arc(direction: .left, radius: .number(10), degrees: .number(360)),
        .goThrough(throughX: .number(0), throughY: .number(0), x: .number(0), y: .number(0)),
        .repeatLoop(times: .number(10)),
        .loopEnd,
        .forever,
        .loopEnd,
        .repeatUntil(condition: .binary(.smallerThan, .number(1), .number(2))),
        .loopEnd,
        .forVariableFromTo(name: "", from: .number(1), to: .number(10)),
        .loopEnd,
        .wait(seconds: .number(1)),
        .waitUntil(condition: .binary(.smallerThan, .number(1), .number(2))),
        .ifThen(condition: .binary(.smallerThan, .number(1), .number(2))),
        .ifEnd,
        .ifElse(condition: .binary(.smallerThan, .number(1), .number(2))),
        .elseBranch,
        .ifEnd,
        .setVariable(name: "", to: .number(1)),
        .changeVariableBy(name: "", value: .number(1)),
        .stitch,
        .setThreadColor(hex: "#ff0000"),
        .runningStitch(length: .number(10)),
        .zigZagStitch(length: .number(2), width: .number(10)),
        .tripleStitch(length: .number(10)),
        .sewUp,
        .stopRunningStitch,
        .writeEmbroideryToFile(name: "embroidery.dst")
    ]

    static let bricks: [Brick] = simpleBricks + compositeBricks + templateBricksAtFreeze
        + formulas.map { .setVariable(name: "v", to: $0) }

    /// Default-valued fields sit beside non-default ones, so a coding that omitted a field at
    /// its default would show in the bytes (Codex slice round, Low).
    static let program = Program(
        name: "Frozen v1 — every case " + sentinel,
        scenes: [
            Scene(name: sentinel, objects: [
                Object(
                    name: "needle",
                    startX: -12.5,
                    startY: 40,
                    startHeading: 135,
                    zIndex: 3,
                    variables: [Variable(name: "local", value: -2.25), Variable(name: "zero")],
                    scripts: [Script(header: .whenStarted, bricks: bricks), Script()]
                ),
                Object()
            ]),
            Scene()
        ],
        variables: [
            Variable(name: "v", value: 5),
            Variable(name: "i", value: 1e-300),
            Variable(name: sentinel, value: 0)
        ]
    )

    /// The v1 payload of every `Brick` case: label and type of each associated value.
    static let brickPayloads: Set<String> = [
        "arc(direction: ArcDirection, radius: Formula, degrees: Formula)",
        "changeVariableBy(name: String, value: Formula)",
        "changeXBy(_: Formula)",
        "changeYBy(_: Formula)",
        "elseBranch",
        "forVariableFromTo(name: String, from: Formula, to: Formula)",
        "forever",
        "goThrough(throughX: Formula, throughY: Formula, x: Formula, y: Formula)",
        "ifElse(condition: Formula)",
        "ifEnd",
        "ifThen(condition: Formula)",
        "loopEnd",
        "moveNSteps(_: Formula)",
        "placeAt(x: Formula, y: Formula)",
        "pointInDirection(_: Formula)",
        "repeatLoop(times: Formula)",
        "repeatUntil(condition: Formula)",
        "runningStitch(length: Formula)",
        "setThreadColor(hex: String)",
        "setVariable(name: String, to: Formula)",
        "setX(_: Formula)",
        "setY(_: Formula)",
        "sewUp",
        "stitch",
        "stopRunningStitch",
        "tripleStitch(length: Formula)",
        "turnLeft(_: Formula)",
        "turnRight(_: Formula)",
        "wait(seconds: Formula)",
        "waitUntil(condition: Formula)",
        "writeEmbroideryToFile(name: String)",
        "zigZagStitch(length: Formula, width: Formula)"
    ]

    /// The v1 payload of every `Formula` case.
    static let formulaPayloads: Set<String> = [
        "binary(_: BinaryOperator, _: Formula, _: Formula)",
        "binaryFunction(_: BinaryFunction, _: Formula, _: Formula)",
        "constant(_: FormulaConstant)",
        "logicalNot(_: Formula)",
        "number(_: Double)",
        "sensor(_: Sensor)",
        "unaryFunction(_: UnaryFunction, _: Formula)",
        "unaryMinus(_: Formula)",
        "variable(_: String)"
    ]

    /// What the program actually holds, collected by walking it, so the coverage claim is
    /// observed rather than restated.
    struct Census {
        var bricks: Set<V1BrickCase> = []
        var headers: Set<V1HeaderCase> = []
        var formulas: Set<FormulaCase> = []
        var operators: Set<V1Operator> = []
        var unaryFunctions: Set<V1UnaryFunction> = []
        var binaryFunctions: Set<V1BinaryFunction> = []
        var constants: Set<V1Constant> = []
        var sensors: Set<V1Sensor> = []
        var arcDirections: Set<V1ArcDirection> = []

        init(_ program: Program) {
            for script in program.scenes.flatMap(\.objects).flatMap(\.scripts) {
                headers.insert(V1HeaderCase(of: script.header))
                for brick in script.bricks {
                    bricks.insert(V1BrickCase(of: brick))
                    if case let .arc(direction, _, _) = brick {
                        arcDirections.insert(V1ArcDirection(of: direction))
                    }
                    for parameter in brick.parameters {
                        if case let .formula(formula) = parameter.value {
                            visit(formula)
                        }
                    }
                }
            }
        }

        private mutating func visit(_ formula: Formula) {
            formulas.insert(FormulaCase(of: formula))
            switch formula {
            case .number, .variable: break
            case let .binary(binaryOperator, lhs, rhs):
                operators.insert(V1Operator(of: binaryOperator))
                visit(lhs)
                visit(rhs)
            case let .unaryMinus(operand), let .logicalNot(operand): visit(operand)
            case let .unaryFunction(function, argument):
                unaryFunctions.insert(V1UnaryFunction(of: function))
                visit(argument)
            case let .binaryFunction(function, first, second):
                binaryFunctions.insert(V1BinaryFunction(of: function))
                visit(first)
                visit(second)
            case let .constant(constant): constants.insert(V1Constant(of: constant))
            case let .sensor(sensor): sensors.insert(V1Sensor(of: sensor))
            }
        }
    }
}
