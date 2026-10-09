@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Testing

/// US-411 test-plan item 6: undo and redo **say what they did**. "Undo" alone is no feedback
/// when the change is off-screen — a loop deleted eight rows up is invisible, and the
/// announcement is all a VoiceOver user gets.
///
/// `UndoStack` keeps snapshots, not actions, so the sentence is worked out from the two
/// programs: the edit being undone or redone is the one that turned the older program into
/// the newer. Each branch is pinned to its **exact English sentence**, so a swapped verb or a
/// swapped direction is a red test, not a plausible-sounding announcement.
@MainActor
@Suite("History announcements")
struct HistoryAnnouncementTests {
    private static let english = Locale(identifier: "en")

    private static func program(_ bricks: [Brick], name: String = "design") -> Program {
        Program(name: name, scenes: [Scene(objects: [Object(scripts: [Script(bricks: bricks)])])])
    }

    private static let loop: [Brick] = [.repeatLoop(times: .number(31)), .stitch, .loopEnd]
    private static let older = program([.sewUp] + loop + [.moveNSteps(.number(10))])

    private static func text(_ direction: HistoryDirection, from: Program, to: Program) -> String {
        HistoryAnnouncement.text(direction, from: from, to: to, locale: english)
    }

    // MARK: The pure sentence

    @Test("undoing a delete names the restored block; redoing it names it as deleted")
    func delete() {
        let newer = Self.program([.sewUp, .moveNSteps(.number(10))])
        #expect(Self.text(.undo, from: newer, to: Self.older) == "Undid deleting Repeat 31 times")
        #expect(Self.text(.redo, from: Self.older, to: newer) == "Redid deleting Repeat 31 times")
    }

    @Test("undoing an add names the removed brick; redoing it names it as added")
    func add() {
        let newer = Self.program([.sewUp] + Self.loop + [.stitch, .moveNSteps(.number(10))])
        #expect(Self.text(.undo, from: newer, to: Self.older) == "Undid adding Stitch")
        #expect(Self.text(.redo, from: Self.older, to: newer) == "Redid adding Stitch")
    }

    /// A leaf moved below a loop. Both readings of a rotation are "one block moved", so the
    /// sentence names the block that is a single leaf or a single pair on its own.
    @Test("undoing a move names the moved brick")
    func move() {
        let newer = Self.program(Self.loop + [.sewUp, .moveNSteps(.number(10))])
        #expect(Self.text(.undo, from: newer, to: Self.older) == "Undid moving Sew up")
        #expect(Self.text(.redo, from: Self.older, to: newer) == "Redid moving Sew up")
    }

    /// `swift-code-reviewer` (Editor UI feature): a lone opener or `loopEnd` is half a pair, not a
    /// block, and naming it is wrong in exactly the commonest drag — a leaf in or out of a loop.
    @Test("a leaf moved out of a loop, upwards, is the brick named")
    func leafOutOfLoop() {
        let inside = Self.program([.repeatLoop(times: .number(31)), .sewUp, .loopEnd])
        let outside = Self.program([.sewUp, .repeatLoop(times: .number(31)), .loopEnd])
        #expect(Self.text(.undo, from: outside, to: inside) == "Undid moving Sew up")
    }

    @Test("a leaf moved into a loop at its end is the brick named")
    func leafIntoLoopEnd() {
        let outside = Self.program([.repeatLoop(times: .number(31)), .loopEnd, .sewUp])
        let inside = Self.program([.repeatLoop(times: .number(31)), .sewUp, .loopEnd])
        #expect(Self.text(.undo, from: inside, to: outside) == "Undid moving Sew up")
    }

    /// The moved block is at the window's back, not its front.
    @Test("a loop moved up over two leaves is named by its opener")
    func pairOverLeaves() {
        let newer = Self.program(Self.loop + [.sewUp, .moveNSteps(.number(10))])
        let older = Self.program([.sewUp, .moveNSteps(.number(10))] + Self.loop)
        #expect(Self.text(.redo, from: older, to: newer) == "Redid moving Repeat 31 times")
    }

    @Test("an added loop is named by its opener, not its end")
    func addedLoop() {
        let newer = Self.program([.sewUp] + Self.loop + Self.loop + [.moveNSteps(.number(10))])
        #expect(Self.text(.undo, from: newer, to: Self.older) == "Undid adding Repeat 31 times")
    }

    /// A parameter edit — including the coalesced declare-and-use pair, whose rows differ in one
    /// brick only. The brick is named **as it reads now**, after the transition.
    @Test("undoing a parameter change names the brick as it now reads")
    func change() {
        let newer = Self.program([.sewUp] + Self.loop + [.moveNSteps(.number(40))])
        #expect(Self.text(.undo, from: newer, to: Self.older) == "Undid changing Move 10 steps")
        #expect(Self.text(.redo, from: Self.older, to: newer) == "Redid changing Move 40 steps")
    }

    @Test("undoing a rename says so")
    func rename() {
        let newer = Self.program([.sewUp] + Self.loop + [.moveNSteps(.number(10))], name: "renamed")
        #expect(Self.text(.undo, from: newer, to: Self.older) == "Undid renaming the design")
        #expect(Self.text(.redo, from: Self.older, to: newer) == "Redid renaming the design")
    }

    /// A declaration on its own changes no row; nor does anything outside the first script.
    @Test("anything else is a generic, still direction-specific sentence")
    func otherEdit() {
        var newer = Self.older
        newer.scenes[0].objects[0].variables = [Variable(name: "Side")]
        #expect(Self.text(.undo, from: newer, to: Self.older) == "Undid an edit")
        #expect(Self.text(.redo, from: Self.older, to: newer) == "Redid an edit")
    }

    // MARK: Through the doors

    private final class Spoken {
        var texts: [String] = []
    }

    private static func editor() -> (EditorViewModel, Spoken) {
        let editor = EditorViewModel(program: older, undoManager: .makeEditorHistory())
        let spoken = Spoken()
        editor.announce = { spoken.texts.append($0) }
        editor.apply(.delete(at: BrickAddress(brickIndex: 1)))
        return (editor, spoken)
    }

    @Test("a toolbar undo and redo each announce once, in order")
    func toolbarAnnounces() {
        let (editor, spoken) = Self.editor()
        #expect(spoken.texts.isEmpty, "an applied edit is not announced by the history")

        editor.undo()
        editor.redo()

        #expect(spoken.texts == [
            String(localized: .historyUndidDeleting("Repeat 31 times")),
            String(localized: .historyRedidDeleting("Repeat 31 times"))
        ])
    }

    @Test("a system undo announces like a toolbar one")
    func systemAnnounces() throws {
        let (editor, spoken) = Self.editor()
        let manager = try #require(editor.systemUndoManager)

        manager.undo()

        #expect(spoken.texts == [String(localized: .historyUndidDeleting("Repeat 31 times"))])
    }

    @Test("an empty undo or redo announces nothing")
    func emptyHistoryIsSilent() {
        let editor = EditorViewModel(program: Self.older, undoManager: nil)
        var spoken: [String] = []
        editor.announce = { spoken.append($0) }

        editor.undo()
        editor.redo()

        #expect(spoken.isEmpty)
    }

    /// Every sentence resolves rather than falling back to its key (`AppStringsTests`' rule).
    @Test("every history sentence resolves to real text")
    func everySentenceResolves() {
        let sentences: [(String, String)] = [
            (String(localized: .historyUndidAdding("X")), "history.undid.adding"),
            (String(localized: .historyRedidAdding("X")), "history.redid.adding"),
            (String(localized: .historyUndidDeleting("X")), "history.undid.deleting"),
            (String(localized: .historyRedidDeleting("X")), "history.redid.deleting"),
            (String(localized: .historyUndidMoving("X")), "history.undid.moving"),
            (String(localized: .historyRedidMoving("X")), "history.redid.moving"),
            (String(localized: .historyUndidChanging("X")), "history.undid.changing"),
            (String(localized: .historyRedidChanging("X")), "history.redid.changing"),
            (String(localized: .historyUndidRenaming), "history.undid.renaming"),
            (String(localized: .historyRedidRenaming), "history.redid.renaming"),
            (String(localized: .historyUndidEdit), "history.undid.edit"),
            (String(localized: .historyRedidEdit), "history.redid.edit")
        ]
        for (text, key) in sentences {
            #expect(!text.isEmpty && !text.hasPrefix("history."), "\(key) did not resolve: \(text)")
        }
    }
}
