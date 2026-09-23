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

        // ADR-032 invariant 2. A generator that rejects everything, or that never
        // produces a loop, satisfies the invariant above perfectly — which is
        // US-309's `drawn=0` capture scoring PASS, one milestone later.
        //
        // The first version of these floors counted `.move` + `.applied` as a
        // move and required no replacement at all. **Codex round 1 constructed a
        // 400-action sequence that passes every one of them while performing zero
        // real relocations and zero replacements**: insert a loop, delete it, a
        // no-op `move(from: i, to: i)`, one rejected `.loopEnd` insert, one
        // out-of-bounds delete, then 395 renames. That does not prove these seeds
        // degenerate — it proves the floors could not have detected it, which is
        // the invariant-2 failure exactly.
        //
        // So the counters now distinguish a *relocation* (the brick list actually
        // changed) from an accepted no-op, count pair moves separately from leaf
        // moves, and require accepted replacements. Renames are excluded from the
        // applied floor entirely, since they can never be rejected and so measure
        // nothing about structural coverage.
        #expect(tally.steps == 400)
        #expect(
            tally.appliedStructuralEdits > 50,
            "seed \(String(seed, radix: 16)) applied only \(tally.appliedStructuralEdits)"
        )
        #expect(tally.appliedLoopOpenerInserts > 0)
        #expect(tally.appliedPairDeletes > 0)
        #expect(tally.appliedPairRelocations > 0)
        #expect(tally.appliedLeafRelocations > 0)
        #expect(tally.appliedReplacements > 0)
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

    /// Item 10b says "**each** addressed action that targets a different,
    /// balanced script", and the version above exercised only `insert`. Codex
    /// round 1 caught the omission, and it is not bookkeeping: adding
    /// `try script.validate()` before `movingPair` — a plausible "be safe" edit —
    /// rejects a perfectly legal move because of an imbalance in *another script
    /// entirely*, and left the whole suite green. Verified by running it.
    @Test("every addressed action applies to a balanced script beside an unbalanced one")
    func everyAddressedActionAppliesBesideAnImbalance() {
        let script = ScriptAddress(scriptIndex: 1) // [.stitch, .forever, .sewUp, .loopEnd]
        let actions: [EditAction] = [
            .insert(.stitch, at: BrickAddress(brickIndex: 1, script: script)),
            .delete(at: BrickAddress(brickIndex: 0, script: script)),
            .move(from: BrickAddress(brickIndex: 1, script: script), to: 0),
            .replaceBrick(at: BrickAddress(brickIndex: 0, script: script), with: .stitch)
        ]
        for action in actions {
            let result = EditorCore.apply(action, to: Fixtures.withStrayLoopEnd)
            if case let .rejected(rejection) = result {
                Issue.record("\(action) should apply beside an unrelated imbalance, got \(rejection)")
                continue
            }
            // …and the imbalance is still there afterwards, unrepaired.
            guard case let .applied(program) = result else { continue }
            #expect(program.scenes[0].objects[0].scripts[0].bricks == [.loopEnd])
        }
    }

    /// The same claim for a **resolvable pair** in the same script as an
    /// unrelated stray end — the case item 10c's counterpart could be misread as
    /// forbidding. `[.loopEnd, .forever, .loopEnd, .stitch]` has a stray end at
    /// index 0 *and* a well-formed pair at 1…2; moving that pair must succeed.
    @Test("a resolvable pair moves even with a stray end elsewhere in the same script")
    func aResolvablePairMovesBesideAStrayEnd() {
        let program = Program(scenes: [Scene(objects: [Object(scripts: [
            Script(bricks: [.loopEnd, .forever, .loopEnd, .stitch])
        ])])])
        var expected = program
        expected.scenes[0].objects[0].scripts[0].bricks = [.forever, .loopEnd, .loopEnd, .stitch]
        #expect(
            EditorCore.apply(.move(from: BrickAddress(brickIndex: 1), to: 0), to: program)
                == .applied(expected)
        )
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
    /// Applied edits that **changed the brick list**. Renames are excluded: they
    /// can never be rejected, so counting them measures the generator's coin
    /// flips rather than the funnel's coverage.
    var appliedStructuralEdits = 0
    var appliedLoopOpenerInserts = 0
    var appliedPairDeletes = 0
    var appliedPairRelocations = 0
    var appliedLeafRelocations = 0
    var appliedReplacements = 0
    var rejectedLoopEndInserts = 0
    var rejectedOutOfBounds = 0

    mutating func record(action: EditAction, result: EditResult, in program: Program) {
        steps += 1
        let before = program.scenes[0].objects[0].scripts[0].bricks

        guard case let .applied(next) = result else {
            switch result {
            case .rejected(.cannotInsertLoopEnd): rejectedLoopEndInserts += 1
            case .rejected(.addressOutOfBounds), .rejected(.destinationOutOfBounds):
                rejectedOutOfBounds += 1
            default: break
            }
            return
        }

        // An accepted no-op is not coverage. This single line is what the first
        // version lacked, and it is what let a 400-step run of renames and
        // `move(from: i, to: i)` satisfy every floor.
        let after = next.scenes[0].objects[0].scripts[0].bricks
        guard before != after else { return }
        appliedStructuralEdits += 1

        switch action {
        case let .insert(kind, _) where kind == .repeatLoop || kind == .forever:
            appliedLoopOpenerInserts += 1
        case let .delete(address)
            where before.indices.contains(address.brickIndex)
            && (before[address.brickIndex].opensLoop || before[address.brickIndex].isLoopEnd):
            appliedPairDeletes += 1
        case let .move(address, _):
            // A pair move and a leaf move take different code paths — the first
            // delegates to `movingPair`, the second is `EditorCore`'s own — so
            // they are counted apart rather than lumped together.
            if before.indices.contains(address.brickIndex), before[address.brickIndex].opensLoop {
                appliedPairRelocations += 1
            } else {
                appliedLeafRelocations += 1
            }
        case .replaceBrick:
            appliedReplacements += 1
        default:
            break
        }
    }
}
