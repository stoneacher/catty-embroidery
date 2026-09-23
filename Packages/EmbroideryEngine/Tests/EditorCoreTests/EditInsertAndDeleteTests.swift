import EditorCore
import ProgramModel
import Testing

/// US-402 test-plan items 2–5: the pair semantics ADR-035 pins for `insert` and
/// `delete`.
@Suite("EditorCore.apply — insert and delete")
struct EditInsertAndDeleteTests {
    typealias Fixtures = EditorCoreFixtures

    // MARK: Insert (items 2 and 3)

    /// Item 2. Inserted **inside** loop A's body rather than at the top level,
    /// because the interesting claim is that `[opener, loopEnd]` nests rather
    /// than splits — inserting between an opener and its own `loopEnd` is the
    /// position that would break a naive implementation.
    @Test("inserting a loop opener inserts both bricks and leaves the script balanced")
    func insertingALoopOpenerStaysBalanced() throws {
        let result = EditorCore.apply(
            .insert(.repeatLoop, at: Fixtures.at(3)),
            to: Fixtures.program
        )
        var expected = Fixtures.bricks
        expected.insert(
            contentsOf: [Brick.repeatLoop(times: .number(BrickDefaults.repeatTimes)), .loopEnd],
            at: 3
        )
        #expect(result == .applied(Fixtures.expecting(expected)))

        guard case let .applied(program) = result else {
            Issue.record("expected .applied")
            return
        }
        for scene in program.scenes {
            for object in scene.objects {
                for script in object.scripts {
                    try script.validate()
                }
            }
        }
    }

    /// `.forever` too, so the claim is about loop openers rather than about
    /// `.repeatLoop` specifically.
    @Test("inserting forever inserts both bricks")
    func insertingForeverStaysBalanced() {
        let result = EditorCore.apply(.insert(.forever, at: Fixtures.at(10)), to: Fixtures.program)
        #expect(result == .applied(Fixtures.expecting(Fixtures.bricks + [.forever, .loopEnd])))
    }

    /// Item 3, asserted as an exact value.
    @Test("inserting a loopEnd is rejected")
    func insertingALoopEndIsRejected() {
        #expect(
            EditorCore.apply(.insert(.loopEnd, at: Fixtures.at(0)), to: Fixtures.program)
                == .rejected(.cannotInsertLoopEnd)
        )
    }

    /// Guard **precedence**, pinned because the tests elsewhere assert exact
    /// rejection values and an implementation that resolved the address first
    /// would answer `.addressOutOfBounds` here instead. One rule, no path
    /// dependence: `insert(.loopEnd, …)` is `.cannotInsertLoopEnd` whatever the
    /// address says.
    @Test("the loopEnd guard precedes address resolution", arguments: [
        BrickAddress(brickIndex: Int.max, script: ScriptAddress(sceneIndex: 99)),
        BrickAddress(brickIndex: -1),
        BrickAddress(brickIndex: 0, script: ScriptAddress(objectIndex: 7, scriptIndex: 7))
    ])
    func loopEndGuardPrecedesAddressResolution(address: BrickAddress) {
        #expect(
            EditorCore.apply(.insert(.loopEnd, at: address), to: Fixtures.program)
                == .rejected(.cannotInsertLoopEnd)
        )
    }

    /// `brickIndex` for `.insert` is an **insertion** index, so `count` is legal
    /// and appends. Milestone exit criterion 1 ("build a program from nothing")
    /// rests on this: an empty script has no position under `0 ..< count`, so the
    /// first brick would otherwise be unaddressable.
    @Test("insert at count appends, and an empty script accepts index 0")
    func insertIsAnInsertionIndex() {
        let appended = EditorCore.apply(.insert(.stitch, at: Fixtures.at(10)), to: Fixtures.program)
        #expect(appended == .applied(Fixtures.expecting(Fixtures.bricks + [.stitch])))

        let empty = Program(scenes: [Scene(objects: [Object(scripts: [Script()])])])
        let seeded = EditorCore.apply(.insert(.stitch, at: BrickAddress(brickIndex: 0)), to: empty)
        var expected = empty
        expected.scenes[0].objects[0].scripts[0].bricks = [.stitch]
        #expect(seeded == .applied(expected))
    }

    // MARK: Delete (items 4 and 5)

    /// Item 4. Ten bricks in, five out — opener, its three-brick body, and its
    /// `loopEnd` (ADR-035, Catroid `BrickController.delete` parity). The counts
    /// are asserted separately from the value so a failure says *how many*
    /// elements went, which is the number the criterion is written in.
    @Test("delete at a loop opener removes the opener, its body and its end")
    func deleteAtOpenerRemovesTheWholePair() {
        let result = EditorCore.apply(.delete(at: Fixtures.at(1)), to: Fixtures.program)
        let expected: [Brick] = [
            .moveNSteps(.number(1)),
            .forever,
            .changeXBy(.number(4)),
            .loopEnd,
            .stopRunningStitch
        ]
        #expect(Fixtures.bricks.count - expected.count == 5)
        #expect(result == .applied(Fixtures.expecting(expected)))
    }

    /// Item 5 — asserted as **equality against the other path**, not as its own
    /// hand-written expectation. A second literal would pass even if both paths
    /// were wrong in the same way; this cannot.
    @Test("delete at a loopEnd redirects to its opener and does exactly the same thing")
    func deleteAtLoopEndRedirectsToTheOpener() {
        #expect(
            EditorCore.apply(.delete(at: Fixtures.at(5)), to: Fixtures.program)
                == EditorCore.apply(.delete(at: Fixtures.at(1)), to: Fixtures.program)
        )
    }

    /// The redirect is a *resolution*, not "delete the previous pair": deleting
    /// at loop B's end must take loop B, not loop A.
    @Test("the redirect resolves the loopEnd's own opener")
    func theRedirectPicksTheRightLoop() {
        #expect(
            EditorCore.apply(.delete(at: Fixtures.at(8)), to: Fixtures.program)
                == EditorCore.apply(.delete(at: Fixtures.at(6)), to: Fixtures.program)
        )
        #expect(
            EditorCore.apply(.delete(at: Fixtures.at(8)), to: Fixtures.program)
                != EditorCore.apply(.delete(at: Fixtures.at(1)), to: Fixtures.program)
        )
    }

    // MARK: Delete on a malformed script

    /// **Decision (Sebastian, 2026-09-23)**, extending ADR-035, which pins delete
    /// only for balanced scripts: an *unresolvable* control brick is deleted as a
    /// leaf.
    ///
    /// The reasoning is ADR-035's own: it chose the `loopEnd`→opener redirect
    /// over a rejection because a row that silently refuses to respond reads as
    /// a bug, and rejecting here recreates exactly that — on a hand-edited file
    /// the offending row would be the one row the user cannot remove.
    ///
    /// **`delete` and `move` deliberately diverge on this input**, and the
    /// asymmetry is not an oversight: `move` is delegated to `movingPair`, a
    /// `ProgramModel` primitive ADR-008 owns and that throws `.unbalancedPair`,
    /// so test 10c requires it stay rejected. `delete` has no such primitive.
    ///
    /// This is not the "apply repairs balance" the acceptance criterion forbids.
    /// That forbids *unsolicited* repair; here the user asked for this row to go.
    @Test("delete at a stray loopEnd removes just that brick")
    func deleteAtAStrayLoopEndRemovesOneBrick() {
        var expected = Fixtures.withStrayLoopEnd
        expected.scenes[0].objects[0].scripts[0].bricks = []
        #expect(
            EditorCore.apply(.delete(at: BrickAddress(brickIndex: 0)), to: Fixtures.withStrayLoopEnd)
                == .applied(expected)
        )
    }

    @Test("delete at an opener with no matching end removes just that brick")
    func deleteAtAnUnclosedOpenerRemovesOneBrick() {
        var expected = Fixtures.withUnclosedOpener
        expected.scenes[0].objects[0].scripts[0].bricks = [.moveNSteps(.number(10))]
        #expect(
            EditorCore.apply(
                .delete(at: BrickAddress(brickIndex: 0)),
                to: Fixtures.withUnclosedOpener
            ) == .applied(expected)
        )
    }
}
