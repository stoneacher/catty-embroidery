import EmbroideryEngine
import ProgramModel
import Samples
import Testing

/// Brick backend slice 7: the bundled sample that shows the new vocabulary.
/// Twelve circles fanned around the centre (Arc), their radius a wave
/// (`sin`), each started from an absolute heading so the chord heading's
/// per-circle drift (ADR-047) cannot unbalance the fan, and a green stem curving
/// down (GoThrough) whose bend is written against a sensor, a token use that
/// reads 0 (see `ArcFlowerProgram.swift`).
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

    /// The petals rose, the stem green. CO 2 alone would pass a change that
    /// came too late and stitched the stem rose (Codex, slice 7). The petals
    /// reach at most 106 points from the centre, so everything below −110 is stem.
    @Test("the stem is stitched in the second colour")
    func stemIsGreen() throws {
        let rose = try #require(ThreadColor(hexString: "#db2777"))
        let green = try #require(ThreadColor(hexString: "#16a34a"))
        let stitches = measured.events.compactMap { event -> (StagePoint, ThreadColor)? in
            if case let .stitch(_, position, _, color) = event {
                (position, color)
            } else {
                nil
            }
        }
        let stem = stitches.filter { $0.0.y < -110 }
        #expect(stem.count > 20)
        #expect(stem.allSatisfy { $0.1 == green })
        #expect(stitches.first?.1 == rose)
    }

    /// Inside ADR-007's 500 × 500 stage, with margin: a sample that runs off the
    /// hoop would greet a first-time user with the "outside the hoop" notice.
    /// Every needle update, not only the stitches: a pattern that skipped a
    /// segment would hide where the needle went (Codex, slice 7).
    @Test("every stitch and every needle update stays inside the hoop")
    func staysInsideTheHoop() {
        let points = measured.events.compactMap { event -> StagePoint? in
            switch event {
            case let .stitch(_, position, _, _): position
            case let .needleMoved(_, update): update.position
            default: nil
            }
        }
        #expect(points.count > 9000)
        for point in points {
            #expect(abs(point.x) < 240 && abs(point.y) < 240, "\(point)")
        }
    }

    /// The figures PROVENANCE states and the Ink/Stitch check reads, pinned so
    /// they cannot drift undefended (`swift-code-reviewer`, slice 7): 821
    /// stitches, all of them records (no interpolation, no jumps), and
    /// x [−99, 99] by y [−212, 99] stage points, 39.6 × 62.2 mm.
    @Test("821 stitches, no jumps, 39.6 by 62.2 millimetres")
    func pinnedFigures() throws {
        #expect(measured.stitchEventCount == 821)
        #expect(measured.stream.count == 821)
        #expect(measured.stream.stitches.allSatisfy { !$0.isJump })
        let bounds = try #require(stageBounds(of: measured.stream))
        #expect(bounds.minX == -99 && bounds.maxX == 99, "\(bounds)")
        #expect(bounds.minY == -212 && bounds.maxY == 99, "\(bounds)")
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
