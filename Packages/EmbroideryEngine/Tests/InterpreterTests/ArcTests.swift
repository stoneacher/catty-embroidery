import EmbroideryEngine
import Foundation
import Interpreter
import ProgramModel
import Testing

/// Brick backend slice 4: Catroid's Arc (`content/actions/ArcAction.kt`), with
/// the brief's D5–D7 adaptations (ADR-047): samples i = 1…100, a degenerate
/// guard, compute-then-commit, catch-and-skip, and the chord heading mirrored.
@Suite("Arc")
struct ArcTests {
    private let scope = VariableScope()
    private let throwing = Formula.binary(.divide, .number(0), .number(0))

    private static func arc(_ direction: ArcDirection, _ radius: Double, _ degrees: Double) -> Brick {
        .arc(direction: direction, radius: .number(radius), degrees: .number(degrees))
    }

    private func close(_ lhs: Double, _ rhs: Double, _ tolerance: Double = 1e-9) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    private func updates(
        _ brick: Brick, from position: StagePoint = StagePoint(x: 0, y: 0), heading: Double = 0
    ) throws -> (updates: [NeedleUpdate], needle: VirtualNeedle) {
        var needle = VirtualNeedle(position: position, heading: heading)
        let emitted = needle.apply(brick, scope: scope)
        let updates = try #require(emitted)
        return (updates, needle)
    }

    // MARK: - Geometry

    /// From (0, 0) facing up, a left arc's centre is 10 to the left, so a
    /// quarter ends at (−10, 10). The heading is the last chord's direction
    /// (D6, mirrored from Catroid): −89.55°, not the tangent's −90°.
    @Test("a quarter left arc ends at (−10, 10), facing along its last chord")
    func quarterLeft() throws {
        let (updates, needle) = try updates(Self.arc(.left, 10, 90))
        #expect(updates.count == 100)
        #expect(close(needle.position.x, -10) && close(needle.position.y, 10))
        #expect(close(needle.heading, -89.55))
        #expect(updates.last == NeedleUpdate(position: needle.position, heading: needle.heading))
    }

    @Test("a quarter right arc ends at (10, 10), facing along its last chord")
    func quarterRight() throws {
        let (_, needle) = try updates(Self.arc(.right, 10, 90))
        #expect(close(needle.position.x, 10) && close(needle.position.y, 10))
        #expect(close(needle.heading, 89.55))
    }

    /// Named so the chord heading is never "fixed" to the tangent by accident.
    @Test("final heading is the last chord, not the tangent")
    func finalHeadingIsTheLastChordNotTheTangent() throws {
        let (_, needle) = try updates(Self.arc(.left, 10, 90))
        #expect(!close(needle.heading, -90, 1e-3))
    }

    /// Each fed sample turns the needle to the chord it just travelled, as
    /// `ArcAction.update` does (`atan2(dx, dy)` is the compass bearing).
    @Test("every update faces along the chord leading to it")
    func everyUpdateFacesItsChord() throws {
        let start = StagePoint(x: 3, y: 4)
        let (updates, _) = try updates(Self.arc(.right, 25, 200), from: start, heading: 30)
        var previous = start
        for update in updates {
            let bearing = atan2(update.position.x - previous.x, update.position.y - previous.y) * 180 / .pi
            #expect(close(update.heading, bearing), "\(update)")
            previous = update.position
        }
    }

    @Test("every sample lies on the arc's circle")
    func everySampleOnTheCircle() throws {
        let start = StagePoint(x: 3, y: 4)
        let heading = 30.0
        let radians = heading * .pi / 180
        // A left arc's centre lies on the heading's left normal (−cos h, sin h).
        let centre = StagePoint(x: start.x - 10 * cos(radians), y: start.y + 10 * sin(radians))
        let (updates, _) = try updates(Self.arc(.left, 10, 270), from: start, heading: heading)
        // Exactly 100 from an off-origin start, where Catroid's i = 0 sample would
        // reconstruct the start with a residual and be fed as a 101st.
        #expect(updates.count == 100)
        for update in updates {
            let distance = hypot(update.position.x - centre.x, update.position.y - centre.y)
            #expect(close(distance, 10), "\(update)")
        }
    }

    @Test("negative degrees turn the other way, negative radius is the same arc")
    func signEquivalences() throws {
        let start = StagePoint(x: -7, y: 2)
        #expect(try updates(Self.arc(.left, 12, -135), from: start, heading: 20).updates
            == updates(Self.arc(.right, 12, 135), from: start, heading: 20).updates)
        #expect(try updates(Self.arc(.right, 12, -135), from: start, heading: 20).updates
            == updates(Self.arc(.left, 12, 135), from: start, heading: 20).updates)
        #expect(try updates(Self.arc(.left, -12, 135), from: start, heading: 20).updates
            == updates(Self.arc(.left, 12, 135), from: start, heading: 20).updates)
    }

    // MARK: - Degenerate, non-finite and bad input: one unchanged update

    /// The last case is Codex's brief-review cancellation input: at 0° every
    /// sample reconstructs the start through `centre + r·(cos, sin)` with a
    /// binary64 residual, so skipping i = 0 alone would still feed and turn.
    @Test("a degenerate arc emits one unchanged update", arguments: [
        (10.0, 0.0, StagePoint(x: 0, y: 0), 0.0),
        (0, 90, StagePoint(x: 0, y: 0), 0),
        (0, 90, StagePoint(x: 5, y: -5), 45),
        (10, 0, StagePoint(x: 0.1, y: 0.2), 33)
    ])
    func degenerate(_ radius: Double, _ degrees: Double, _ start: StagePoint, _ heading: Double) throws {
        let (updates, needle) = try updates(Self.arc(.left, radius, degrees), from: start, heading: heading)
        #expect(updates == [NeedleUpdate(position: start, heading: heading)])
        #expect(needle == VirtualNeedle(position: start, heading: heading))
    }

    /// The guard is structural: exactly 0°. A *near*-zero sweep, such as
    /// `sin(180)` = 1.2e-16 that ADR-046 deliberately keeps, samples points a
    /// rounding residual away from the start, feeds them, and turns the needle
    /// along those residual chords, as Catroid does. Pinned so the choice is
    /// visible (ADR-047; `swift-code-reviewer`, PR 2 feature review).
    @Test("a near-zero sweep keeps Catroid's residual steering", arguments: [1.2246467991473532e-16, 1e-13])
    func nearZeroSweepSteers(_ degrees: Double) throws {
        let start = StagePoint(x: 0.1, y: 0.2)
        let (updates, needle) = try updates(Self.arc(.left, 10, degrees), from: start, heading: 33)
        #expect(!updates.isEmpty)
        #expect(close(needle.position.x, start.x, 1e-12) && close(needle.position.y, start.y, 1e-12))
        #expect(needle.heading != 33)
    }

    /// `r = MAX` makes `centre + r·cos` overflow to ±∞ partway round; nothing
    /// is committed, so the needle never holds a non-finite coordinate.
    @Test("an arc whose samples overflow leaves the needle unchanged")
    func overflowSkips() throws {
        let (updates, needle) = try updates(Self.arc(.left, .greatestFiniteMagnitude, 180), heading: 0)
        #expect(updates == [NeedleUpdate(position: StagePoint(x: 0, y: 0), heading: 0)])
        #expect(needle == VirtualNeedle())
    }

    /// Catch-and-skip like `moveNSteps` (ADR-018), not Catroid's accident of
    /// stitching from the stage origin with unassigned action fields.
    @Test("a bad formula skips the arc")
    func badFormulaSkips() throws {
        let start = StagePoint(x: 4, y: 4)
        for brick in [
            Brick.arc(direction: .left, radius: throwing, degrees: .number(90)),
            .arc(direction: .left, radius: .number(10), degrees: throwing)
        ] {
            let (updates, needle) = try updates(brick, from: start, heading: 10)
            #expect(updates == [NeedleUpdate(position: start, heading: 10)])
            #expect(needle == VirtualNeedle(position: start, heading: 10))
        }
    }

    /// D5's pinned divergence (Codex brief review, finding 1): Catroid stores
    /// the look's position as `float`, so at 2³⁰ a radius-20 arc never changes
    /// it and nothing is stitched. The needle is `Double` (ADR-014), so here it
    /// moves and feeds every sample.
    @Test("at large coordinates the Double needle still moves (pinned divergence)")
    func largeCoordinateFeedDivergence() throws {
        let start = StagePoint(x: 1_073_741_824, y: 1_073_741_824)
        let (updates, needle) = try updates(Self.arc(.left, 20, 90), from: start)
        #expect(updates.count == 100)
        #expect(close(needle.position.x, start.x - 20, 1e-6) && close(needle.position.y, start.y + 20, 1e-6))
    }

    /// A radius far below the start's ulp reconstructs the start exactly at every
    /// sample: no chord, so nothing is fed and the heading is kept. Feeding
    /// zero chords would turn the needle to `atan2(0, 0)` = 0° (`swift-code-reviewer`,
    /// slice 4).
    @Test("an arc too small to move the needle keeps its heading")
    func zeroChordKeepsHeading() throws {
        let start = StagePoint(x: 5, y: 5)
        let (updates, needle) = try updates(Self.arc(.left, 1e-300, 90), from: start, heading: 33)
        #expect(updates == [NeedleUpdate(position: start, heading: 33)])
        #expect(needle == VirtualNeedle(position: start, heading: 33))
    }

    /// A start heading reaches the needle unreduced, so the arc must reduce it
    /// mod 360 before converting to radians: 90 + 360·2⁴⁰ is exactly 90 mod 360,
    /// and its arc is the same arc (`swift-code-reviewer`, slice 4).
    @Test("an arc from a huge equivalent heading is the same arc")
    func headingReducedBeforeRadians() throws {
        let huge = 90 + 360 * 1_099_511_627_776.0
        #expect(try updates(Self.arc(.right, 15, 120), heading: huge).updates
            == updates(Self.arc(.right, 15, 120), heading: 90).updates)
    }
}
