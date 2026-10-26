@testable import catrobat_embroidery_ios
import EditorCore
import EmbroideryEngine
import Foundation
import ProgramModel
import Projects
import Samples
import Testing

// The wiring the slice 5 review found unpinned (Codex and `swift-code-reviewer`), on
// `ProjectWiringTests`' fixtures.

extension ProjectWiringTests {
    /// Codex, slice 5: the lifecycle retry is the other door a first write can come through.
    @Test("a draft whose first save failed becomes a project when the lifecycle retry writes it")
    func aRetriedFirstSaveGivesTheDraftAFile() throws {
        let app = App()
        let model = app.window()
        model.select(Self.coil)
        let draft = model.projectID
        app.store.failingSaves = [draft]
        model.editor.apply(Self.editQ)
        try #require(app.store.saves.isEmpty, "the premise: the first save failed")

        app.store.failingSaves = []
        model.sceneDidLeaveActive()

        #expect(app.store.program(draft) == model.editor.program)
        #expect(app.remembered.id == draft)
        #expect(try app.library.uniquedName(DesignName.validating("M5 Q").get()).value == "M5 Q 2",
                "the file's own name now takes the place of the draft's")
    }

    /// Codex, slice 5: a draft that cannot be written yet still holds its *current* name.
    @Test("an unwritten draft reserves its current name, not the one it started with")
    func anUnwrittenDraftReservesItsCurrentName() throws {
        let app = App()
        let model = app.window()
        model.select(Self.coil)
        app.store.failingSaves = [model.projectID]

        model.editor.apply(Self.editQ)

        #expect(try app.library.uniquedName(DesignName.validating("M5 Q").get()).value == "M5 Q 2")
        #expect(try app.library.uniquedName(DesignName.validating("Square Coil").get()).value == "Square Coil")
    }

    /// `swift-code-reviewer`, slice 5: the window must not reserve its own name against itself.
    @Test("picking the same sample again in an untouched draft keeps its name")
    func rePickingKeepsTheName() {
        let app = App()
        let model = app.window()

        let names = (0 ..< 3).map { _ in
            model.select(Self.coil)
            return model.editor.program.name
        }

        #expect(names == ["Square Coil", "Square Coil", "Square Coil"])
    }

    /// A draft registers its uniqued name, so a third window avoids the second's too.
    @Test("three windows picking one sample get three distinct names")
    func threeWindowsGetThreeNames() {
        let app = App()
        let windows = (0 ..< 3).map { _ in app.window() }

        for window in windows {
            window.select(Self.rosette)
        }

        #expect(windows.map(\.editor.program.name) == ["Octagon Rosette", "Octagon Roset 2", "Octagon Roset 3"])
    }

    /// The window's held revision belongs to the project it held: a sample picked after an
    /// edit is a fresh draft with nothing to write.
    @Test("leaving the foreground after picking a sample writes nothing for the new draft")
    func aPickAfterAnEditHoldsNoRevision() {
        let app = App([Self.stored: .program(Self.rosette.program)])
        let model = app.window(scene: Self.stored)
        model.editor.apply(Self.editQ)

        model.select(Self.coil)
        model.sceneDidLeaveActive()

        #expect(app.store.saves.map(\.id) == [Self.stored])
    }

    /// Last *opened*, not last edited: editing a project another window opened earlier does not
    /// make it the one a relaunch reopens.
    @Test("an edit to an opened project does not make it the last opened again")
    func editingDoesNotMarkOpened() {
        let other = ProjectID.fixed(2)
        let app = App([Self.stored: .program(Self.rosette.program), other: .program(Self.coil.program)])
        let windowA = app.window(scene: Self.stored)
        _ = app.window(scene: other)

        windowA.editor.apply(Self.editQ)

        #expect(app.remembered.id == other)
    }

    /// The save fails, so the disk still holds the original: a second launch would read it back
    /// over the edit.
    /// Hardening (`swift-code-reviewer`, slice 5): should the root view ever disappear and
    /// appear again, the window must hold its project again rather than edit it unregistered.
    @Test("launching again after closing registers the window's project again")
    func relaunchingReRegisters() {
        let app = App([Self.stored: .program(Self.rosette.program)])
        let model = app.window(scene: Self.stored)
        model.close()

        model.launch(sceneID: Self.stored)

        #expect(app.library.holders(of: Self.stored) == [model.window])
    }

    /// The alert reports the refusal even when the last opened project opened instead.
    @Test("a refused scene project is alerted for even when the last opened one opens")
    func aRefusalIsAlertedBesideAFallback() throws {
        let last = ProjectID.fixed(2)
        let app = App(
            [Self.stored: .refused(.corrupt, name: nil), last: .program(Self.coil.program)], lastOpened: last
        )

        let model = app.window(scene: Self.stored)

        #expect(model.projectID == last)
        #expect(try #require(model.launchRefusal).reason == .document(.corrupt))
    }

    /// Codex, PR #78 round 4 (and `swift-code-reviewer`'s slice 5 note): a change whose save
    /// failed must not be thrown away by picking a sample. The pick retries the save first.
    @Test("picking a sample after a failed save retries it, and switches once it is written")
    func aPickRetriesAFailedSave() {
        let app = App([Self.stored: .program(Self.rosette.program)])
        let model = app.window(scene: Self.stored)
        app.store.failingSaves = [Self.stored]
        model.editor.apply(Self.editQ)
        let edited = model.editor.program
        app.store.failingSaves = []

        model.select(Self.coil)

        #expect(app.store.program(Self.stored) == edited)
        #expect(model.projectID != Self.stored)
    }

    /// If the retry fails too, the window stays on the unsaved program, its failure showing,
    /// rather than discarding it.
    @Test("picking a sample while the save keeps failing keeps the unsaved program on screen")
    func aPickKeepsAnUnsavableProgram() {
        let app = App([Self.stored: .program(Self.rosette.program)])
        let model = app.window(scene: Self.stored)
        app.store.failingSaves = [Self.stored]
        model.editor.apply(Self.editQ)
        let edited = model.editor.program

        model.select(Self.coil)

        #expect(model.projectID == Self.stored)
        #expect(model.editor.program == edited)
        #expect(model.saveFailure == .saveFailed)
    }

    /// Codex, PR #78 round 5: a retry that another window's newer revision supersedes is a
    /// deliberate drop, not a failed write, so it must not keep the window from leaving.
    @Test("a retry superseded by another window's newer save lets the window leave")
    func aSupersededRetryLetsTheWindowLeave() {
        let app = App([Self.stored: .program(Self.rosette.program)])
        let windowA = app.window(scene: Self.stored)
        let windowB = app.window(scene: Self.stored)
        app.store.failingSaves = [Self.stored]
        windowA.editor.apply(Self.editQ)
        windowB.editor.apply(Self.editR)
        windowB.close()
        app.store.failingSaves = []

        windowA.select(Self.coil)

        #expect(windowA.projectID != Self.stored)
        #expect(app.store.program(Self.stored) == Self.rosette.program, "the older revision is not written")
    }
}
