@testable import catrobat_embroidery_ios
import EditorCore
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
        var undos = 0, redos = 0
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
        var generator = Generator(seed: seed)
        let editor = EditorViewModel(program: .blank, undoManager: nil)
        var tally = Tally()

        for step in 0 ..< Self.steps {
            let before = Self.bricks(editor)
            let count = before.count
            // Keep the script between a handful and ~40 bricks, so moves and deletes have room
            // and pairs keep being nested and crossed.
            let roll = generator.next() % 100
            let door: UInt64 = count < 6 ? 0 : (count > 40 ? 60 : roll)

            switch door {
            case 0 ..< 30:
                editor.selectedBrickIndex = count == 0 || generator.next() % 4 == 0
                    ? nil : Int(generator.next() % UInt64(count))
                // Loops are 2 of the palette's kinds; a third of the inserts pick one, so pairs are
                // nested and crossed often enough for the pair floors to mean something.
                let kinds = generator.next() % 3 == 0 ? [BrickKind.repeatLoop, .forever] : Self.paletteKinds
                let kind = try #require(kinds.randomElement(using: &generator))
                if editor.insert(kind) != nil, Self.bricks(editor) != before {
                    tally.inserts += 1
                    if kind == .repeatLoop || kind == .forever {
                        tally.loopInserts += 1
                    }
                }
            case 30 ..< 55:
                let from = Int(generator.next() % UInt64(count))
                let to = Int(generator.next() % UInt64(count + 1))
                editor.moveRows(fromOffsets: [from], toOffset: to)
                if Self.bricks(editor) != before {
                    tally.drags += 1
                    if Self.isLoopBrick(before[from]) {
                        tally.pairDrags += 1
                    }
                }
            case 55 ..< 75:
                let index = Int(generator.next() % UInt64(count))
                editor.deleteRows(atOffsets: [index])
                if Self.bricks(editor) != before {
                    tally.deletes += 1
                    if Self.isLoopBrick(before[index]) {
                        tally.pairDeletes += 1
                    }
                }
            case 75 ..< 90:
                let rows = BrickRowPresentation.rows(for: editor.program)
                let row = rows[Int(generator.next() % UInt64(rows.count))]
                let actions = [
                    row.moveUp, row.moveDown, row.moveAboveLoop,
                    row.moveBelowLoop, row.moveIntoLoopAbove, row.moveIntoLoopBelow
                ].compactMap(\.self)
                if let action = actions.randomElement(using: &generator) {
                    editor.apply(action)
                    if Self.bricks(editor) != before {
                        tally.accessibilityMoves += 1
                    }
                }
            default:
                // Redo is reachable only straight after an undo (any edit clears it), so this band
                // is a burst: undo one to three steps, then redo up to as many — each step checked.
                let undoCount = 1 + Int(generator.next() % 3)
                for _ in 0 ..< undoCount where editor.undo() {
                    tally.undos += 1
                    try Self.expectBalanced(editor, seed: seed, step: step)
                }
                for _ in 0 ..< Int(generator.next() % UInt64(undoCount + 1)) where editor.redo() {
                    tally.redos += 1
                    try Self.expectBalanced(editor, seed: seed, step: step)
                }
            }

            try Self.expectBalanced(editor, seed: seed, step: step)
        }

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
    }
}
