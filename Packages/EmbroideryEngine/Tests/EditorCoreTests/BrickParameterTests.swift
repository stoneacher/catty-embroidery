import EditorCore
import ProgramModel
import Samples
import Testing

/// US-410 test-first items 1, 2, 7c and 10, the package half: what a brick's
/// parameters are, which editor each one gets, and how one parameter is
/// replaced without touching anything else.
///
/// `Brick.replacing(_:with:)` is the only way the parameter editor builds a
/// replacement, so "a parameter edit never changes the kind" (item 10) is a
/// property of this function, swept over every kind and every slot below,
/// rather than a promise at each call site.
@Suite("Brick parameters")
struct BrickParameterTests {
    // MARK: 1 — the slots each kind has

    /// Exhaustive by construction: the expectation is a switch over
    /// `BrickKind` with no `default:`, so a new kind fails to compile here
    /// before it can reach the editor without slots.
    private static func expectedSlots(of kind: BrickKind) -> [ParameterSlot] {
        switch kind {
        case .moveNSteps: [.steps]
        case .turnLeft, .turnRight, .pointInDirection: [.degrees]
        case .placeAt: [.x, .y]
        case .setX, .changeXBy: [.x]
        case .setY, .changeYBy: [.y]
        case .repeatLoop: [.times]
        case .wait: [.seconds]
        case .setVariable, .changeVariableBy: [.variableName, .value]
        case .runningStitch, .tripleStitch: [.length]
        case .zigZagStitch: [.length, .width]
        case .setThreadColor: [.hex]
        case .writeEmbroideryToFile: [.fileName]
        case .forever, .loopEnd, .stitch, .sewUp, .stopRunningStitch: []
        }
    }

    @Test("every kind's template lists its slots in sentence order", arguments: BrickKind.allCases)
    func templateSlots(kind: BrickKind) {
        let head = kind.template()[0]
        #expect(head.parameters.map(\.slot) == Self.expectedSlots(of: kind))
    }

    /// The values are read back, not merely the slots: a `parameters` that
    /// returned the right slots with the template's defaults would pass the
    /// test above for every template.
    @Test("parameters read the brick's own values, in order")
    func parametersReadValues() {
        #expect(
            Brick.zigZagStitch(length: .number(3), width: .variable("W")).parameters == [
                BrickParameter(slot: .length, value: .formula(.number(3))),
                BrickParameter(slot: .width, value: .formula(.variable("W")))
            ]
        )
        #expect(
            Brick.setVariable(name: "Side", to: .number(9)).parameters == [
                BrickParameter(slot: .variableName, value: .variableName("Side")),
                BrickParameter(slot: .value, value: .formula(.number(9)))
            ]
        )
        #expect(
            Brick.setThreadColor(hex: "#1d4ed8").parameters
                == [BrickParameter(slot: .hex, value: .threadColor(hex: "#1d4ed8"))]
        )
        #expect(
            Brick.writeEmbroideryToFile(name: "a.dst").parameters
                == [BrickParameter(slot: .fileName, value: .fileName("a.dst"))]
        )
    }

    // MARK: 1 — the editor each value gets

    @Test("each value maps to its editor")
    func editorKinds() {
        let difference = Formula.binary(.divide, .number(360), .variable("Inner Loop"))
        let negated = Formula.unaryMinus(.variable("Side"))
        #expect(ParameterEditorKind(.formula(.number(10))) == .number(10))
        #expect(ParameterEditorKind(.formula(.variable("Side"))) == .variableReference("Side"))
        #expect(ParameterEditorKind(.formula(difference)) == .readOnlyFormula(difference, reason: .binary))
        #expect(ParameterEditorKind(.formula(negated)) == .readOnlyFormula(negated, reason: .unaryMinus))
        #expect(ParameterEditorKind(.variableName("Side")) == .variableName("Side"))
        #expect(ParameterEditorKind(.threadColor(hex: "#ff0000")) == .threadColor(hex: "#ff0000"))
        #expect(ParameterEditorKind(.fileName("a.dst")) == .fileName("a.dst"))
    }

    /// `-5` typed on the pad is `.number(-5)` (US-404), but a persisted
    /// `.unaryMinus(.number(5))` is still a tree the pad cannot write back
    /// byte-identically. One rule: every `.unaryMinus` is read-only.
    @Test("a negated literal is read-only too, not a number")
    func negatedLiteralIsReadOnly() {
        let negated = Formula.unaryMinus(.number(5))
        #expect(ParameterEditorKind(.formula(negated)) == .readOnlyFormula(negated, reason: .unaryMinus))
    }

    /// The story's own count, re-derived from the shipped samples rather than
    /// restated: 8 non-literal nodes in 6 parameters — Rosette 4 parameters
    /// (2 `.binary`, 2 `.variable`), Coil 2 `.variable`. Read-only means
    /// `.binary` here, since neither sample holds a `.unaryMinus`.
    @Test("the shipped samples' parameters map as counted at planning")
    func sampleParameters() {
        func editors(_ id: SampleID) -> [ParameterEditorKind] {
            let program = SampleLibrary[id].program
            return program.scenes.flatMap(\.objects).flatMap(\.scripts).flatMap(\.bricks)
                .flatMap(\.parameters).map { ParameterEditorKind($0.value) }
        }
        func count(_ id: SampleID, _ predicate: (ParameterEditorKind) -> Bool) -> Int {
            editors(id).filter(predicate).count
        }
        let isReadOnly: (ParameterEditorKind) -> Bool = {
            if case .readOnlyFormula(_, .binary) = $0 {
                true
            } else {
                false
            }
        }
        let isReference: (ParameterEditorKind) -> Bool = {
            if case .variableReference = $0 {
                true
            } else {
                false
            }
        }
        #expect(count(.octagonRosette, isReadOnly) == 2)
        #expect(count(.octagonRosette, isReference) == 2)
        #expect(count(.squareCoil, isReadOnly) == 0)
        #expect(count(.squareCoil, isReference) == 2)
    }

    // MARK: 2 — one slot replaced, everything else kept

    @Test("replacing one slot rebuilds the whole brick with only that slot changed")
    func replacingOneSlot() {
        let zigzag = Brick.zigZagStitch(length: .number(3), width: .number(7))
        #expect(
            zigzag.replacing(.width, with: .formula(.number(12)))
                == .zigZagStitch(length: .number(3), width: .number(12))
        )
        #expect(
            zigzag.replacing(.length, with: .formula(.number(4)))
                == .zigZagStitch(length: .number(4), width: .number(7))
        )
        let placeAt = Brick.placeAt(x: .number(1), y: .number(2))
        #expect(placeAt.replacing(.y, with: .formula(.number(-2))) == .placeAt(x: .number(1), y: .number(-2)))
        #expect(placeAt.replacing(.x, with: .formula(.number(-1))) == .placeAt(x: .number(-1), y: .number(2)))
        let set = Brick.setVariable(name: "A", to: .number(1))
        #expect(set.replacing(.variableName, with: .variableName("B")) == .setVariable(name: "B", to: .number(1)))
        #expect(set.replacing(.value, with: .formula(.number(2))) == .setVariable(name: "A", to: .number(2)))
        #expect(
            Brick.changeVariableBy(name: "A", value: .number(1)).replacing(.value, with: .formula(.number(3)))
                == .changeVariableBy(name: "A", value: .number(3))
        )
        #expect(Brick.setThreadColor(hex: "#ff0000").replacing(.hex, with: .threadColor(hex: "#1d4ed8"))
            == .setThreadColor(hex: "#1d4ed8"))
        #expect(Brick.writeEmbroideryToFile(name: "a").replacing(.fileName, with: .fileName("b"))
            == .writeEmbroideryToFile(name: "b"))
    }

    /// Every single-formula kind, with a value distinct from its template's,
    /// so a `replacing` that ignored the value would return the template.
    @Test("every formula slot of every template accepts a new number", arguments: BrickKind.allCases)
    func everyFormulaSlotAcceptsANumber(kind: BrickKind) {
        let head = kind.template()[0]
        for parameter in head.parameters {
            guard case .formula = parameter.value else { continue }
            let replaced = head.replacing(parameter.slot, with: .formula(.number(4242)))
            let read = replaced?.parameters.first { $0.slot == parameter.slot }?.value
            #expect(read == .formula(.number(4242)), "\(kind).\(parameter.slot)")
        }
    }

    /// The string slots too: `replacing` ends in a `default: nil`, so a new kind with a string
    /// slot would compile and refuse every write without this sweep (review finding 9).
    @Test("every string slot of every template accepts a new value", arguments: BrickKind.allCases)
    func everyStringSlotAcceptsAValue(kind: BrickKind) {
        let head = kind.template()[0]
        for parameter in head.parameters {
            let value: ParameterValue
            switch parameter.value {
            case .formula: continue
            case .variableName: value = .variableName("Fresh")
            case .threadColor: value = .threadColor(hex: "#123456")
            case .fileName: value = .fileName("fresh.dst")
            }
            let replaced = head.replacing(parameter.slot, with: value)
            let read = replaced?.parameters.first { $0.slot == parameter.slot }?.value
            #expect(read == value, "\(kind).\(parameter.slot)")
        }
    }

    // MARK: 7c — number to variable and back

    @Test("a number parameter switches to a variable and back, each a whole brick")
    func numberToVariableAndBack() throws {
        let move = Brick.moveNSteps(.number(10))
        let referenced = try #require(move.replacing(.steps, with: .formula(.variable("Side"))))
        #expect(referenced == .moveNSteps(.variable("Side")))
        #expect(referenced.replacing(.steps, with: .formula(.number(10))) == move)
    }

    // MARK: 10 — never a different kind

    /// Every slot × every value shape × every kind: the answer is either `nil`
    /// or a brick of the same kind. The values include the mismatched shapes
    /// (a hex into a formula slot), which must be refused rather than coerced.
    @Test("no replacement ever changes the brick's kind", arguments: BrickKind.allCases)
    func neverAnotherKind(kind: BrickKind) {
        let values: [ParameterValue] = [
            .formula(.number(1)), .formula(.variable("v")), .variableName("v"),
            .threadColor(hex: "#000000"), .fileName("f")
        ]
        let head = kind.template()[0]
        for slot in ParameterSlot.allCases {
            for value in values {
                if let replaced = head.replacing(slot, with: value) {
                    #expect(BrickKind(of: replaced) == kind, "\(kind).\(slot) ← \(value)")
                }
            }
        }
    }

    /// The refusal side of item 10, asserted so a `replacing` that returned
    /// `self` for every mismatch could not pass as "same kind".
    @Test("a slot the brick does not have, or a value of the wrong shape, is refused")
    func mismatchIsRefused() {
        #expect(Brick.moveNSteps(.number(1)).replacing(.x, with: .formula(.number(2))) == nil)
        #expect(Brick.moveNSteps(.number(1)).replacing(.steps, with: .threadColor(hex: "#000000")) == nil)
        #expect(Brick.setThreadColor(hex: "#ff0000").replacing(.hex, with: .fileName("x")) == nil)
        #expect(Brick.setVariable(name: "", to: .number(1)).replacing(.variableName, with: .formula(.number(1))) == nil)
        #expect(Brick.stitch.replacing(.steps, with: .formula(.number(1))) == nil)
    }
}
