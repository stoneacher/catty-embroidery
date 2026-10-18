import EmbroideryEngine
import ProgramModel
import Samples
import Testing

/// Brick backend slice 7: the bundled sample that shows the new vocabulary.
/// Twelve circles fanned around the centre (Arc), their radius a wave
/// (`sin`), each started from an absolute heading so the chord heading's
/// per-circle drift (ADR-047) cannot unbalance the fan, and a green stem curving
/// down (GoThrough) whose bend is measured from the needle's own position (a
/// sensor).
@Suite("Arc flower")
struct ArcFlowerTests {
    private var sample: SampleProgram {
        SampleLibrary[.arcFlower]
    }

    private var measured: SampleRun {
        run(sample)
    }

    private var bricks: [Brick] {
        sample.program.scenes.flatMap(\.objects).flatMap(\.scripts).flatMap(\.bricks)
    }

    /// The point of the sample: it must use what this feature added, or it is
    /// one more design that could have shipped in M4.
    @Test("the sample uses Arc, GoThrough, a math function and a sensor")
    func usesTheNewVocabulary() {
        #expect(bricks.contains {
            if case .arc = $0 {
                true
            } else {
                false
            }
        })
        #expect(bricks.contains {
            if case .goThrough = $0 {
                true
            } else {
                false
            }
        })
        let formulas = bricks.flatMap(\.formulasForTest)
        #expect(formulas.contains { $0.containsNode {
            if case .unaryFunction = $0 {
                true
            } else {
                false
            }
        } })
        #expect(formulas.contains { $0.containsNode {
            if case .sensor = $0 {
                true
            } else {
                false
            }
        } })
    }

    /// The petals in one colour, the stem in another: one effective change, so
    /// the header reads CO 2 (ADR-015).
    @Test("two colour blocks")
    func twoColourBlocks() throws {
        #expect(measured.stream.colorChangeCount == 1)
        let header = try DSTHeader(stream: measured.stream, name: sample.program.name)
        #expect(coField(of: header) == 2)
    }

    /// Inside ADR-007's 500 × 500 stage, with margin: a sample that runs off the
    /// hoop would greet a first-time user with the "outside the hoop" notice.
    @Test("every stitch stays inside the hoop")
    func staysInsideTheHoop() {
        let stitches = measured.events.compactMap { event -> StagePoint? in
            if case let .stitch(_, position, _, _) = event {
                position
            } else {
                nil
            }
        }
        #expect(stitches.count > 500)
        for point in stitches {
            #expect(abs(point.x) < 240 && abs(point.y) < 240, "\(point)")
        }
    }

    /// Absolute headings per circle: each petal returns to the centre and
    /// points to exactly 0°, 30°, … 330°, whatever drift the chord heading left.
    @Test("each circle starts from its own absolute heading")
    func circlesStartFromAbsoluteHeadings() {
        let atCentre = measured.events.compactMap { event -> Double? in
            guard case let .needleMoved(_, update) = event, update.position == StagePoint(x: 0, y: 0) else {
                return nil
            }
            return update.heading
        }
        for petal in 0 ..< 12 {
            #expect(atCentre.contains(Double(petal) * 30), "no circle starts at \(petal * 30)°")
        }
    }
}

private extension Brick {
    /// Every formula the brick carries, for the vocabulary check.
    var formulasForTest: [Formula] {
        switch self {
        case let .moveNSteps(formula), let .turnLeft(formula), let .turnRight(formula), let .pointInDirection(formula),
             let .setX(formula), let .setY(formula), let .changeXBy(formula), let .changeYBy(formula),
             let .repeatLoop(formula), let .wait(formula), let .setVariable(_, formula),
             let .changeVariableBy(_, formula),
             let .runningStitch(formula), let .tripleStitch(formula):
            [formula]
        case let .placeAt(x, y): [x, y]
        case let .zigZagStitch(length, width): [length, width]
        case let .arc(_, radius, degrees): [radius, degrees]
        case let .goThrough(throughX, throughY, x, y): [throughX, throughY, x, y]
        case .forever, .loopEnd, .stitch, .setThreadColor, .sewUp, .stopRunningStitch, .writeEmbroideryToFile:
            []
        }
    }
}

private extension Formula {
    /// Whether any node of the tree satisfies `predicate`.
    func containsNode(_ predicate: (Formula) -> Bool) -> Bool {
        if predicate(self) {
            return true
        }
        return switch self {
        case .number, .variable, .constant, .sensor: false
        case let .unaryMinus(operand), let .unaryFunction(_, operand): operand.containsNode(predicate)
        case let .binary(_, lhs, rhs), let .binaryFunction(_, lhs, rhs):
            lhs.containsNode(predicate) || rhs.containsNode(predicate)
        }
    }
}
