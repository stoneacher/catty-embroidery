@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Testing

/// M4 exit criterion 4, slice 2 of the Editor UI feature: **no sequence of adds, reorders and
/// deletes can produce a script that fails `Script.validate()`**, asserted as a property over
/// generated sequences.
///
/// `EditBalanceInvariantTests` already proves it for `EditorCore.apply` over generated
/// `EditAction`s. This soak proves it **one layer up, through the doors the UI actually uses**:
/// the palette's insert at the selection, the list's `.onMove` offsets (pre-removal, converted
/// by `moveRows`), its `.onDelete`, the rows' VoiceOver move actions, and undo and redo. Each of
/// those converts or composes before `apply` sees anything, and a conversion that is not
/// pair-aware would build an action `apply` accepts and still split a loop.
///
/// Every step is followed by `validate()`, and the run must actually exercise each door —
/// including **pair** moves and deletes — or a generator that degenerated into appending
/// leaves would pass while testing nothing (the non-vacuity floors, ADR-032 invariant 2).
@MainActor
@Suite("Pair invariant soak through the editor's doors")
struct PairInvariantSoakTests {
    /// SplitMix64, copied for the reason `EditorCoreFixtures` gives: test targets cannot share
    /// helpers.
    private struct Generator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }

    /// What the run actually did, counted only when the program changed.
    private struct Tally {
        var inserts = 0, loopInserts = 0
        var drags = 0, pairDrags = 0
        var deletes = 0, pairDeletes = 0
        var accessibilityMoves = 0
        var undos = 0, redos = 0, systemSteps = 0
    }

    private static let paletteKinds = PaletteGroup.allCases.flatMap(\.kinds)
    private static let steps = 1500

    private static func bricks(_ editor: EditorViewModel) -> [Brick] {
        editor.program.scenes.first?.objects.first?.scripts.first?.bricks ?? []
    }

    private static func isLoopBrick(_ brick: Brick) -> Bool {
        switch BrickKind(of: brick) {
        case .repeatLoop, .forever, .loopEnd: true
        default: false
        }
    }

    /// Every script in the program validates. The first unbalanced step records itself and ends
    /// the run, so the failure names the step that broke it rather than every step after.
    private static func expectBalanced(_ editor: EditorViewModel, seed: UInt64, step: Int) throws {
        for scene in editor.program.scenes {
            for object in scene.objects {
                for script in object.scripts {
                    do {
                        try script.validate()
                    } catch {
                        Issue.record("seed \(seed), step \(step): \(error) in \(script.bricks)")
                        throw error
                    }
                }
            }
        }
    }

    @Test("adds, drags, deletes, VoiceOver moves, undo and redo never unbalance the script",
          arguments: [UInt64(1), 7, 2026])
    func soak(seed: UInt64) throws {
        var run = Run(seed: seed)
        for step in 0 ..< Self.steps {
            try run.step(step)
        }
        let tally = run.tally

        // Non-vacuity: every door was walked, pairs included.
        #expect(tally.inserts >= 200, "\(tally)")
        #expect(tally.loopInserts >= 20, "\(tally)")
        #expect(tally.drags >= 100, "\(tally)")
        #expect(tally.pairDrags >= 20, "\(tally)")
        #expect(tally.deletes >= 100, "\(tally)")
        #expect(tally.pairDeletes >= 20, "\(tally)")
        #expect(tally.accessibilityMoves >= 100, "\(tally)")
        #expect(tally.undos >= 20, "\(tally)")
        #expect(tally.redos >= 10, "\(tally)")
        #expect(tally.systemSteps >= 20, "\(tally)")
    }

    /// One seeded run: the editor, the generator and what the run has done so far.
    @MainActor
    private struct Run {
        let seed: UInt64
        let editor = EditorViewModel(program: .blank, undoManager: .makeEditorHistory())
        var generator: Generator
        var tally = Tally()

        init(seed: UInt64) {
            self.seed = seed
            generator = Generator(seed: seed)
        }

        /// One step through a random door, then the balance check.
        mutating func step(_ step: Int) throws {
            let before = PairInvariantSoakTests.bricks(editor)
            // Keep the script between a handful and ~40 bricks, so moves and deletes have room
            // and pairs keep being nested and crossed.
            let roll = generator.next() % 100
            let door: UInt64 = before.count < 6 ? 0 : (before.count > 40 ? 60 : roll)
            switch door {
            case 0 ..< 30: try insert(before)
            case 30 ..< 55: try drag(before, step)
            case 55 ..< 75: delete(before)
            case 75 ..< 90: try accessibilityMove(before, step)
            default: try history(step)
            }
            try PairInvariantSoakTests.expectBalanced(editor, seed: seed, step: step)
            try expectAgreement(step)
            try expectRowIdentity(step)
        }

        /// One distinct row ID per brick after every step (ADR-034's 2026-10-15 amendment): a
        /// duplicate would make SwiftUI merge two rows, a missing one would leave a row without
        /// identity.
        private func expectRowIdentity(_ step: Int) throws {
            let count = PairInvariantSoakTests.bricks(editor).count
            let ids = editor.rowIDs
            try #require(
                ids.count == count && Set(ids).count == count,
                "seed \(seed), step \(step): \(ids.count) IDs, \(Set(ids).count) distinct, \(count) bricks"
            )
        }

        /// The system manager offers undo and redo exactly when the toolbar does (US-411), after
        /// every step of the random sequence — not only the hand-picked ones `UndoBridgeTests`
        /// walks.
        private func expectAgreement(_ step: Int) throws {
            let manager = try #require(editor.systemUndoManager)
            let system = (manager.canUndo, manager.canRedo)
            let toolbar = (editor.canUndo, editor.canRedo)
            try #require(system == toolbar, "seed \(seed), step \(step): system \(system), toolbar \(toolbar)")
        }

        /// Half the history steps go through the system manager, as a shake would.
        private mutating func systemOrToolbar(_ direction: HistoryDirection) throws -> Bool {
            guard random(below: 2) == 0 else {
                return direction == .undo ? editor.undo() : editor.redo()
            }
            let manager = try #require(editor.systemUndoManager)
            guard direction == .undo ? manager.canUndo : manager.canRedo else { return false }
            if direction == .undo {
                manager.undo()
            } else {
                manager.redo()
            }
            tally.systemSteps += 1
            return true
        }

        private mutating func random(below bound: Int) -> Int {
            Int(generator.next() % UInt64(bound))
        }

        private func changed(from before: [Brick]) -> Bool {
            PairInvariantSoakTests.bricks(editor) != before
        }

        private mutating func insert(_ before: [Brick]) throws {
            editor.selectedBrickIndex = before.isEmpty || random(below: 4) == 0
                ? nil : random(below: before.count)
            // Loops are 2 of the palette's kinds; a third of the inserts pick one, so pairs are
            // nested and crossed often enough for the pair floors to mean something.
            let loops: [BrickKind] = [.repeatLoop, .forever]
            let kinds = random(below: 3) == 0 ? loops : PairInvariantSoakTests.paletteKinds
            let kind = try #require(kinds.randomElement(using: &generator))
            guard editor.insert(kind) != nil, changed(from: before) else { return }
            tally.inserts += 1
            tally.loopInserts += loops.contains(kind) ? 1 : 0
        }

        private mutating func drag(_ before: [Brick], _ step: Int) throws {
            let from = random(below: before.count)
            let toOffset = random(below: before.count + 1)
            // The same conversion `moveRows` makes, so the move's destination is known.
            let action = Script(bricks: before).moveAction(fromOffsets: [from], toOffset: toOffset, in: ScriptAddress())
            let idsBefore = editor.rowIDs
            editor.moveRows(fromOffsets: [from], toOffset: toOffset)
            guard changed(from: before) else { return }
            tally.drags += 1
            tally.pairDrags += PairInvariantSoakTests.isLoopBrick(before[from]) ? 1 : 0
            try expectMovedIDs(action, before: before, idsBefore: idsBefore, step)
        }

        private mutating func delete(_ before: [Brick]) {
            let index = random(below: before.count)
            editor.deleteRows(atOffsets: [index])
            guard changed(from: before) else { return }
            tally.deletes += 1
            tally.pairDeletes += PairInvariantSoakTests.isLoopBrick(before[index]) ? 1 : 0
        }

        private mutating func accessibilityMove(_ before: [Brick], _ step: Int) throws {
            let rows = BrickRowPresentation.rows(for: editor.program)
            let row = rows[random(below: rows.count)]
            let actions = [
                row.moveUp, row.moveDown, row.moveAboveLoop,
                row.moveBelowLoop, row.moveIntoLoopAbove, row.moveIntoLoopBelow
            ].compactMap(\.self)
            guard let action = actions.randomElement(using: &generator) else { return }
            let idsBefore = editor.rowIDs
            editor.apply(action)
            guard changed(from: before) else { return }
            tally.accessibilityMoves += 1
            try expectMovedIDs(action, before: before, idsBefore: idsBefore, step)
        }

        /// Where the IDs went, not only that they stay unique (Codex round 1): a move never
        /// changes which bricks exist, so **every ID must still label a brick equal to the one it
        /// labelled before**. Equal bricks may trade IDs (`RowIdentities`), so this is the exact
        /// promise — a nested loop moved across its parent's end, left unrecognised, puts the inner
        /// opener's ID on a `loopEnd` and fails it.
        private func expectMovedIDs(_ action: EditAction?, before: [Brick], idsBefore: [Int], _ step: Int) throws {
            guard case .move = action else { return }
            let after = PairInvariantSoakTests.bricks(editor)
            let ids = editor.rowIDs
            let oldIndex = Dictionary(uniqueKeysWithValues: idsBefore.enumerated().map { ($1, $0) })
            for (newIndex, id) in ids.enumerated() {
                let old = try #require(oldIndex[id], "seed \(seed), step \(step): a move minted ID \(id)")
                try #require(
                    before[old] == after[newIndex],
                    "seed \(seed), step \(step): ID \(id) moved from \(before[old]) to \(after[newIndex])"
                )
            }
        }

        /// Redo is reachable only straight after an undo (any edit clears it), so this door is a
        /// burst: undo one to three steps, then redo up to as many — each step checked.
        private mutating func history(_ step: Int) throws {
            let undoCount = 1 + random(below: 3)
            for _ in 0 ..< undoCount where try systemOrToolbar(.undo) {
                tally.undos += 1
                try PairInvariantSoakTests.expectBalanced(editor, seed: seed, step: step)
                try expectAgreement(step)
            }
            for _ in 0 ..< random(below: undoCount + 1) where try systemOrToolbar(.redo) {
                tally.redos += 1
                try PairInvariantSoakTests.expectBalanced(editor, seed: seed, step: step)
                try expectAgreement(step)
            }
        }
    }
}
