import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

/// Variables slice 4 (brief D5, D8; ADR-049): RepeatUntil as Catroid's `RepeatUntilAction`
/// (`RepeatUntilAction.kt:60-79`) inside libgdx's one-child-per-frame sequence.
///
/// - **Truthiness** is `interpretDouble(...) != 0.0` — not truncated, so `0.5` ends the loop.
///   A condition that does not interpret (NaN) ends it.
/// - **Two checks.** On entering an iteration (so zero iterations are possible), and at the
///   body's end in the same tick as its last brick. A body that ends with the condition false
///   enters the next iteration in the next tick, where the entry check reads it again — so a
///   write from another script in between is seen.
/// - **Pinned divergence:** Catroid also re-checks validity at the start of every frame, so a
///   condition that turns NaN mid-body ends the loop mid-body; here only the iteration
///   boundaries check it.
/// - A loop that exits at entry takes no tick of its own, as a zero-count repeat (ADR-018).
@Suite("RepeatUntil execution")
struct RepeatUntilTests {
    static let nan = Formula.binary(.divide, .number(0), .number(0))

    static func tag(_ y: Double) -> Brick {
        .setY(.number(y))
    }

    static func until(_ condition: Formula, _ body: [Brick]) -> [Brick] {
        [.repeatUntil(condition: condition)] + body + [.loopEnd]
    }

    @Test("a condition true at entry runs the body zero times", arguments: [
        Formula.constant(.true), .number(0.5), .number(-0.99), .number(.greatestFiniteMagnitude), nan
    ])
    func zeroIterations(_ condition: Formula) {
        #expect(tagProfile(scripts: [Self.until(condition, [Self.tag(1)]) + [Self.tag(2)]]) == [[2]])
    }

    /// The body runs one brick per tick until the end check finds the condition true; the loop
    /// then exits in that tick and the next brick waits for the next one.
    @Test("the body repeats until the condition holds at its end")
    func repeatsUntilTrue() {
        let bricks = Self.until(.binary(.equal, .variable("v"), .number(3)), [
            .changeVariableBy(name: "v", value: .number(1)), .setY(.variable("v"))
        ]) + [Self.tag(9)]
        #expect(tagProfile(scripts: [bricks]) == [[], [1], [], [2], [], [3], [9]])
    }

    /// The end check runs in the tick of the body's last brick: B resets `v` in that tick, after
    /// A. Checked at the end, A has already left; checked only at the next entry, A would see
    /// `v = 0` and run the body again.
    @Test("the end check runs in the same tick as the body's last brick")
    func endCheckSameTick() {
        let profile = tagProfile(scripts: [
            Self.until(.binary(.equal, .variable("v"), .number(1)), [
                Self.tag(1), .setVariable(name: "v", to: .number(1))
            ]) + [Self.tag(2)],
            [.setVariable(name: "dummy", to: .number(0)), .setVariable(name: "v", to: .number(0))]
        ])
        #expect(profile == [[1], [], [2]])
    }

    /// The entry check of the next iteration reads again: B sets the flag in the tick A's body
    /// ends with it false; A's next entry sees it and leaves, without running the body.
    @Test("the next iteration's entry reads a flag another script set in between")
    func entryRecheck() {
        let profile = tagProfile(scripts: [
            Self.until(.binary(.equal, .variable("stop"), .number(1)), [Self.tag(1)]) + [Self.tag(2)],
            [.setVariable(name: "stop", to: .number(1))]
        ])
        #expect(profile == [[1], [2]])
    }

    /// Pinned divergence (brief D8). The body sets `w = 0`, which makes the condition
    /// `c − 0 ÷ w` NaN until it sets `w = 1` again. Catroid ends the loop at the next frame's
    /// validity check, before `y1`; here the body runs on and the end check exits normally.
    @Test("a condition that turns NaN mid-body is not checked until the body ends (pinned divergence)")
    func midBodyNaNDivergence() {
        let condition = Formula.binary(.minus, .variable("c"), .binary(.divide, .number(0), .variable("w")))
        let bricks: [Brick] = [.setVariable(name: "w", to: .number(1))] + Self.until(condition, [
            .setVariable(name: "w", to: .number(0)), Self.tag(1),
            .changeVariableBy(name: "c", value: .number(1)), .setVariable(name: "w", to: .number(1))
        ]) + [Self.tag(2)]
        #expect(tagProfile(scripts: [bricks]) == [[], [], [1], [], [], [2]])
    }

    @Test("a RepeatUntil reached after an action reads its condition in the next tick")
    func deferredAfterAnAction() {
        let profile = tagProfile(scripts: [
            [Self.tag(1)] + Self.until(.binary(.equal, .variable("stop"), .number(1)), [Self.tag(5)]) + [Self.tag(2)],
            [.setVariable(name: "stop", to: .number(1))]
        ])
        #expect(profile == [[1], [2]])
    }

    @Test("an empty body checks twice per tick and never spins")
    func emptyBody() {
        let profile = tagProfile(scripts: [
            Self.until(.binary(.equal, .variable("stop"), .number(1)), []) + [Self.tag(2)],
            [.wait(seconds: .number(0.1)), .setVariable(name: "stop", to: .number(1))]
        ])
        #expect(profile.last == [2])
        #expect(profile.count < 10)
    }

    @Test("a RepeatUntil re-enters fresh inside an outer loop")
    func nestedReentry() {
        let bricks: [Brick] = [.repeatLoop(times: .number(2)), .setVariable(name: "v", to: .number(0))]
            + Self.until(.binary(.equal, .variable("v"), .number(2)), [
                .changeVariableBy(name: "v", value: .number(1)), .setY(.variable("v"))
            ]) + [.loopEnd]
        #expect(tagProfile(scripts: [bricks]).flatMap(\.self) == [1, 2, 1, 2])
    }
}
