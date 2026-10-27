@testable import catrobat_embroidery_ios
import Projects
import Testing

/// The project a window holds and how far it has got (project management slice 7, extracted
/// from `AppModel`): a draft has no file until its first write, and only a change holds a
/// revision (brief D3; ADR-037 3b).
@MainActor
@Suite("Window project")
struct WindowProjectTests {
    @Test("a draft has no file and no revision, and reserves its name")
    func draft() {
        let project = WindowProject.draft(.fixed(1))

        #expect(project.id == .fixed(1))
        #expect(!project.hasFile)
        #expect(project.heldRevision == nil)
        #expect(project.draftName("Flower") == "Flower")
    }

    @Test("an opened project has a file and no revision, and reserves no name")
    func opened() {
        let project = WindowProject.opened(.fixed(2))

        #expect(project.id == .fixed(2))
        #expect(project.hasFile)
        #expect(project.heldRevision == nil)
        #expect(project.draftName("Flower") == nil)
    }

    @Test("a change holds its revision, and a later change replaces it")
    func changeHoldsRevision() {
        let library = ProjectLibrary.inMemory()
        let first = library.mintRevision()
        let second = library.mintRevision()
        var project = WindowProject.opened(.fixed(1))

        project.changed(first)
        #expect(project.heldRevision == first)
        project.changed(second)
        #expect(project.heldRevision == second)
    }

    @Test("a draft's first write gives it a file and says so, once")
    func firstWrite() {
        var project = WindowProject.draft(.fixed(1))

        let first = project.written()
        #expect(first)
        #expect(project.hasFile)
        #expect(project.draftName("Flower") == nil)
        let second = project.written()
        #expect(!second)
    }

    @Test("a write to an opened project is not a first write")
    func writeToOpened() {
        var project = WindowProject.opened(.fixed(1))

        let first = project.written()
        #expect(!first)
        #expect(project.hasFile)
    }
}
