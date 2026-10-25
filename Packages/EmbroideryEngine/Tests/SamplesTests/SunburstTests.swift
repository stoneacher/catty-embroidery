import EmbroideryEngine
import Foundation
import ProgramModel
import Samples
import Testing

/// Variables slice 8: the bundled sample that shows the Variables feature. Thirty-six rays
/// around the centre, counted by a For loop whose variable places each tip and valley, long
/// and short in turn by an If/Else on a variable the branches flip, and a circle in a second
/// colour in the middle (see `SunburstProgram.swift`).
@Suite("Sunburst")
struct SunburstTests {
    private var sample: SampleProgram {
        SampleLibrary[.sunburst]
    }

    /// One run per test: Swift Testing builds a fresh suite value for each.
    private let measured = run(SampleLibrary[.sunburst])

    private var bricks: [Brick] {
        sample.program.scenes.flatMap(\.objects).flatMap(\.scripts).flatMap(\.bricks)
    }

    /// The point of the sample: it uses what the feature added, a For loop and an If/Else whose
    /// condition is one comparison of a variable and a number, so it opens in the comparison
    /// editor rather than locked.
    @Test("the sample uses a For loop and an If/Else on a plain comparison")
    func usesTheNewVocabulary() throws {
        #expect(bricks.contains {
            if case .forVariableFromTo(name: "Ray", from: _, to: _) = $0 { true } else { false }
        })
        let condition = try #require(bricks.lazy.compactMap { brick -> Formula? in
            if case let .ifElse(condition) = brick { condition } else { nil }
        }.first)
        guard case let .binary(.equal, .variable, .number) = condition else {
            Issue.record("not a comparison of a variable and a number: \(condition)")
            return
        }
    }

    /// Amber rays, a red circle: one effective change, so the header reads CO 2 (ADR-015).
    @Test("two colour blocks")
    func twoColourBlocks() throws {
        #expect(measured.stream.colorChangeCount == 1)
        let header = try DSTHeader(stream: measured.stream, name: sample.program.name)
        #expect(coField(of: header) == 2)
    }

    private var stitches: [(point: StagePoint, color: ThreadColor)] {
        measured.events.compactMap { event in
            if case let .stitch(_, position, _, color) = event { (position, color) } else { nil }
        }
    }

    private static func radius(_ point: StagePoint) -> Double {
        (point.x * point.x + point.y * point.y).squareRoot()
    }

    /// Eighteen long rays and eighteen short ones, each tip on its own heading. A ray that
    /// skipped the If's flip, or a For that reused a heading, leaves fewer distinct tips. Tips
    /// are the needle's own positions, not stitches, whose phase carries across moves.
    @Test("eighteen long and eighteen short rays, alternating around the centre")
    func raysAlternate() {
        let tips = measured.events.compactMap { event -> StagePoint? in
            guard case let .needleMoved(_, update) = event, Self.radius(update.position) > 50 else { return nil }
            return update.position
        }
        #expect(tips.allSatisfy { abs(Self.radius($0) - 150) < 1e-6 || abs(Self.radius($0) - 85) < 1e-6 })
        // ADR-007: 0° is up, clockwise; a tip's heading in whole tens of degrees.
        func heading(_ point: StagePoint) -> Int {
            let degrees = atan2(point.x, point.y) * 180 / .pi
            return Int((degrees + 360).rounded()) % 360
        }
        let long = Set(tips.filter { Self.radius($0) > 100 }.map(heading))
        let short = Set(tips.filter { Self.radius($0) < 100 }.map(heading))
        #expect(long == Set(stride(from: 5, through: 345, by: 20)))
        #expect(short == Set(stride(from: 15, through: 355, by: 20)))
    }

    /// The circle is the red block, and it sits in the middle only: the second colour starts
    /// after every ray is stitched. Its stitches lie inside the valleys' 40-point radius: the
    /// circle's own 35, the step in from the last valley, and the tie-off tack.
    @Test("the circle is stitched in the second colour, in the middle")
    func circleIsRed() throws {
        let amber = try #require(ThreadColor(hexString: "#f59e0b"))
        let red = try #require(ThreadColor(hexString: "#ff0000"))
        #expect(stitches.first?.color == amber)
        let circle = stitches.filter { $0.color == red }
        #expect(circle.count > 40)
        let outermost = circle.map { Self.radius($0.point) }.max() ?? 0
        #expect(outermost <= 40, "\(outermost)")
        #expect(stitches.filter { Self.radius($0.point) > 140 }.allSatisfy { $0.color == amber })
        // Inside the valleys' 40 there are only the step in and the circle, so all of it is red:
        // a colour change one Arc late would leave an eighth of the circle amber and pass every
        // count above (Codex, slice 8).
        let inner = stitches.filter { Self.radius($0.point) < 39.5 }
        #expect(inner.count > 40)
        #expect(inner.allSatisfy { $0.color == red })
    }

    /// The figures PROVENANCE states and the Ink/Stitch check reads, pinned so they cannot drift
    /// undefended: 123 ticks, 1429 stitches, all records (no jumps), x and y [−147, 147] stage
    /// points, 58.8 mm square. The ticks are 3 over the library's 120 floor, so a restructuring
    /// fails here on its own figure first (`swift-code-reviewer`, slice 8).
    @Test("123 ticks, 1429 stitches, no jumps, 58.8 millimetres square")
    func pinnedFigures() throws {
        #expect(measured.ticks == 123)
        #expect(measured.stitchEventCount == 1429)
        #expect(measured.stream.count == 1429)
        #expect(measured.stream.stitches.allSatisfy { !$0.isJump })
        let bounds = try #require(stageBounds(of: measured.stream))
        #expect(bounds.minX == -147 && bounds.maxX == 147, "\(bounds)")
        #expect(bounds.minY == -147 && bounds.maxY == 147, "\(bounds)")
    }

    @Test("every stitch and every needle update stays inside the hoop")
    func staysInsideTheHoop() {
        let points = measured.events.compactMap { event -> StagePoint? in
            switch event {
            case let .stitch(_, position, _, _): position
            case let .needleMoved(_, update): update.position
            default: nil
            }
        }
        #expect(points.count > 1000)
        for point in points {
            #expect(abs(point.x) < 240 && abs(point.y) < 240, "\(point)")
        }
    }
}
