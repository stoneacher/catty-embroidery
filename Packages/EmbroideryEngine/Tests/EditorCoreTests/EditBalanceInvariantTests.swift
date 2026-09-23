import EditorCore
import ProgramModel
import Testing

/// US-402 test-plan items 10 and 10b — the acceptance criterion that balance is
/// **preserved, not enforced**, in both directions.
///
/// Milestone exit criterion 4 rests on the first half of this suite, and the
/// milestone README is explicit that it is written as a property rather than a
/// scenario because it is a claim about *everything the user can do*.
@Suite("EditorCore.apply — balance is preserved, not enforced")
struct EditBalanceInvariantTests {
    typealias Fixtures = EditorCoreFixtures

    /// Item 10. Three independent seeds, each reported as its own case with its
    /// own generator instance, so a failure names the seed that produced it.
    /// Swift Testing has no shrinking; a reproducible seed plus the step index
    /// and the action in every message is the substitute.
    @Test("no applied action ever unbalances a balanced program",
          arguments: [0x5EED_0001, 0x5EED_0002, 0x5EED_0003] as [UInt64])
    func appliedActionsPreserveBalance(seed: UInt64) throws {
        var generator = SplitMix64(seed: seed)
        var program = Fixtures.propertySeed
        var tally = Tally()

        for step in 0 ..< 400 {
            let action = Fixtures.randomAction(against: program, using: &generator)
            let result = EditorCore.apply(action, to: program)
            tally.record(action: action, result: result, in: program)

            switch result {
            case let .applied(next):
                for script in next.scenes[0].objects[0].scripts {
                    do {
                        try script.validate()
                    } catch {
                        Issue.record("""
                        seed \(String(seed, radix: 16)) step \(step): \(action) \
                        produced an unbalanced script — \(error)
                        bricks: \(script.bricks)
                        """)
                        return
                    }
                }
                program = next
            case .rejected:
                break
            }
        }

        // ADR-032 invariant 2. A generator that rejects everything, or that
        // never produces a loop, satisfies the invariant above perfectly — which
        // is US-309's `drawn=0` capture scoring PASS, one milestone later. These
        // floors are what make the property a claim rather than a hope.
        #expect(tally.steps == 400)
        #expect(tally.applied > 100, "seed \(String(seed, radix: 16)) applied only \(tally.applied)")
        #expect(tally.appliedLoopOpenerInserts > 0)
        #expect(tally.appliedPairDeletes > 0)
        #expect(tally.appliedMoves > 0)
        #expect(tally.rejectedLoopEndInserts > 0)
        #expect(tally.rejectedOutOfBounds > 0)
    }

    /// Item 10b, the preservation counterpart, in its named counterexample form:
    /// `.renameProgram` on a program containing a bare `[.loopEnd]` **applies**,
    /// and the script still fails `validate()` afterwards.
    ///
    /// This is the half that an over-eager implementation breaks — one that
    /// validates the whole program before accepting an edit would reject here,
    /// and one that repaired the imbalance would leave a program the user never
    /// asked for.
    @Test("renaming a program that contains an unbalanced script applies and repairs nothing")
    func renameLeavesAPreExistingImbalanceAlone() {
        var expected = Fixtures.withStrayLoopEnd
        expected.name = "New"
        let result = EditorCore.apply(.renameProgram("New"), to: Fixtures.withStrayLoopEnd)
        #expect(result == .applied(expected))

        guard case let .applied(program) = result else { return }
        #expect(throws: ScriptValidationError.unmatchedLoopEnd(index: 0)) {
            try program.scenes[0].objects[0].scripts[0].validate()
        }
    }

    /// The addressed half of item 10b: an imbalance in a *different* script does
    /// not reject an action targeting a balanced one, and does not get repaired
    /// on the way past.
    @Test("an imbalance elsewhere does not change an action's own outcome")
    func anImbalanceElsewhereIsIrrelevant() {
        let address = BrickAddress(
            brickIndex: 1,
            script: Fixtures.balancedScriptBesideTheStrayEnd
        )
        var expected = Fixtures.withStrayLoopEnd
        expected.scenes[0].objects[0].scripts[1].bricks = [.stitch, .stitch, .forever, .sewUp, .loopEnd]

        let result = EditorCore.apply(.insert(.stitch, at: address), to: Fixtures.withStrayLoopEnd)
        #expect(result == .applied(expected))

        guard case let .applied(program) = result else { return }
        #expect(program.scenes[0].objects[0].scripts[0].bricks == [.loopEnd])
    }

    /// The acceptance criterion's own worked counterexample, which exists to stop
    /// the "insert of a loop opener yields a balanced script" promise from being
    /// written unconditionally: inserting a repeat into `[loopEnd, moveNSteps(10)]`
    /// gives `[loopEnd, moveNSteps(10), repeatLoop(10), loopEnd]`, which
    /// **must be accepted** — preservation — and which **does not validate**.
    ///
    /// The two halves contradict each other unless the promise is qualified, so
    /// both are asserted here in one test rather than left implicit.
    @Test("inserting a loop opener into an unbalanced script is accepted and stays unbalanced")
    func insertingIntoAnUnbalancedScriptIsAcceptedAndNotRepaired() {
        let program = Program(scenes: [Scene(objects: [Object(scripts: [
            Script(bricks: [.loopEnd, .moveNSteps(.number(10))])
        ])])])
        var expected = program
        expected.scenes[0].objects[0].scripts[0].bricks = [
            .loopEnd,
            .moveNSteps(.number(10)),
            .repeatLoop(times: .number(BrickDefaults.repeatTimes)),
            .loopEnd
        ]

        let result = EditorCore.apply(
            .insert(.repeatLoop, at: BrickAddress(brickIndex: 2)),
            to: program
        )
        #expect(result == .applied(expected))

        guard case let .applied(edited) = result else { return }
        #expect(throws: ScriptValidationError.unmatchedLoopEnd(index: 0)) {
            try edited.scenes[0].objects[0].scripts[0].validate()
        }
    }

    /// The same claim for the *same* script: the acceptance criterion says an
    /// imbalance "elsewhere in the same script" also leaves the action's own
    /// outcome unchanged. Deleting the trailing leaf of
    /// `[repeatLoop(2), moveNSteps(10)]` succeeds even though the opener above it
    /// is unclosed.
    @Test("an imbalance elsewhere in the same script does not reject an unrelated edit")
    func anImbalanceInTheSameScriptIsIrrelevant() {
        var expected = Fixtures.withUnclosedOpener
        expected.scenes[0].objects[0].scripts[0].bricks = [.repeatLoop(times: .number(2))]
        #expect(
            EditorCore.apply(
                .delete(at: BrickAddress(brickIndex: 1)),
                to: Fixtures.withUnclosedOpener
            ) == .applied(expected)
        )
    }
}

/// Non-vacuity bookkeeping for the property above. A plain `struct` mutated by
/// the test's own local `var` — nothing shared, so parallel execution is safe.
private struct Tally {
    var steps = 0
    var applied = 0
    var appliedLoopOpenerInserts = 0
    var appliedPairDeletes = 0
    var appliedMoves = 0
    var rejectedLoopEndInserts = 0
    var rejectedOutOfBounds = 0

    mutating func record(action: EditAction, result: EditResult, in program: Program) {
        steps += 1
        let bricks = program.scenes[0].objects[0].scripts[0].bricks

        switch (action, result) {
        case let (.insert(kind, _), .applied) where kind == .repeatLoop || kind == .forever:
            applied += 1
            appliedLoopOpenerInserts += 1
        case (.insert(.loopEnd, _), .rejected(.cannotInsertLoopEnd)):
            rejectedLoopEndInserts += 1
        case let (.delete(address), .applied)
            where bricks.indices.contains(address.brickIndex)
            && (bricks[address.brickIndex].opensLoop || bricks[address.brickIndex].isLoopEnd):
            applied += 1
            appliedPairDeletes += 1
        case (.move, .applied):
            applied += 1
            appliedMoves += 1
        case (_, .applied):
            applied += 1
        case (_, .rejected(.addressOutOfBounds)), (_, .rejected(.destinationOutOfBounds)):
            rejectedOutOfBounds += 1
        case (_, .rejected):
            break
        }
    }
}
