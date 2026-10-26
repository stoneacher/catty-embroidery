@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Samples
import Testing

/// Which project a window opens on (project management slice 5, brief D6): the scene's ID if
/// it names an openable project, else the last opened one on the same condition, else
/// nothing — and the window starts a draft under a fresh ID. Resolved by the library, so the
/// rule is tested without a window.
@MainActor
@Suite("Project launch")
struct ProjectLaunchTests {
    private static let rosette = SampleLibrary[.octagonRosette].program
    private static let coil = SampleLibrary[.squareCoil].program
    private static let scene = ProjectID.fixed(1)
    private static let last = ProjectID.fixed(2)

    private static func library(
        _ entries: [ProjectID: InMemoryProjectStore.Entry],
        lastOpened: ProjectID? = nil
    ) -> (ProjectLibrary, LastOpenedProject) {
        let remembered = LastOpenedProject.disposable()
        remembered.id = lastOpened
        return (ProjectLibrary(store: InMemoryProjectStore(entries), lastOpened: remembered), remembered)
    }

    @Test("with nothing stored, nothing opens and nothing is refused")
    func nothingStored() {
        let (library, _) = Self.library([:])

        #expect(library.resolveLaunch(sceneID: nil) == LaunchResolution(opened: nil, refusals: []))
    }

    @Test("the scene's project opens first, and becomes the last opened")
    func theSceneOpens() {
        let (library, remembered) = Self.library(
            [Self.scene: .program(Self.rosette), Self.last: .program(Self.coil)], lastOpened: Self.last
        )

        let resolution = library.resolveLaunch(sceneID: Self.scene)

        #expect(resolution.opened == OpenedProject(id: Self.scene, program: Self.rosette))
        #expect(remembered.id == Self.scene)
    }

    @Test("a scene ID with no file falls back to the last opened project")
    func aMissingSceneFallsBack() {
        let (library, remembered) = Self.library([Self.last: .program(Self.coil)], lastOpened: Self.last)

        let resolution = library.resolveLaunch(sceneID: Self.scene)

        #expect(resolution.opened == OpenedProject(id: Self.last, program: Self.coil))
        #expect(remembered.id == Self.last)
    }

    @Test("a last opened ID with no file is cleared, and nothing opens")
    func aMissingLastIsCleared() {
        let (library, remembered) = Self.library([:], lastOpened: Self.last)

        let resolution = library.resolveLaunch(sceneID: nil)

        #expect(resolution.opened == nil)
        #expect(remembered.id == nil)
    }

    /// A refused candidate is reported under its own ID and skipped; it stays the last opened,
    /// because its file is still there.
    @Test("a refused scene project is reported and skipped for the last opened one")
    func aRefusedSceneIsSkipped() {
        let (library, _) = Self.library(
            [Self.scene: .refused(.unsupportedVersion(2), name: "Future"), Self.last: .program(Self.coil)],
            lastOpened: Self.last
        )

        let resolution = library.resolveLaunch(sceneID: Self.scene)

        #expect(resolution.refusals == [ProjectRefusal(id: Self.scene, reason: .document(.unsupportedVersion(2)))])
        #expect(resolution.opened == OpenedProject(id: Self.last, program: Self.coil))
    }

    @Test("a refused last opened project is reported once, even when it is also the scene's")
    func aRefusedCandidateIsReportedOnce() {
        let (library, remembered) = Self.library([Self.last: .refused(.corrupt, name: nil)], lastOpened: Self.last)

        let resolution = library.resolveLaunch(sceneID: Self.last)

        #expect(resolution == LaunchResolution(
            opened: nil, refusals: [ProjectRefusal(id: Self.last, reason: .document(.corrupt))]
        ))
        #expect(remembered.id == Self.last)
    }

    @Test("a project deleted in this process does not open from a stale scene ID")
    func aDeletedSceneDoesNotOpen() throws {
        let (library, _) = Self.library([Self.scene: .program(Self.rosette)])
        try library.delete(Self.scene)

        #expect(library.resolveLaunch(sceneID: Self.scene).opened == nil)
    }

    /// Codex, slice 5: the tombstone skips the deleted ID before the "missing" branch could
    /// clear it, so the delete itself must.
    @Test("deleting the last opened project clears it")
    func deletingTheLastOpenedClearsIt() throws {
        let (library, remembered) = Self.library(
            [Self.last: .program(Self.coil), Self.scene: .program(Self.rosette)], lastOpened: Self.last
        )

        try library.delete(Self.scene)
        #expect(remembered.id == Self.last, "deleting another project leaves it")
        try library.delete(Self.last)

        #expect(remembered.id == nil)
    }

    // MARK: The stored form

    /// Decoded defensively: whatever else is under the key reads as "nothing stored".
    @Test("the last opened ID is stored as its UUID string, and anything else reads as none")
    func theStoredForm() throws {
        let defaults = try #require(UserDefaults(suiteName: "launch-tests-\(UUID().uuidString)"))
        let remembered = LastOpenedProject(defaults: defaults)

        remembered.id = Self.last
        #expect(defaults.string(forKey: LastOpenedProject.key) == "00000000-0000-0000-0000-000000000002")
        #expect(LastOpenedProject(defaults: defaults).id == Self.last)

        for garbage: Any in ["not a uuid", 42, ["a"]] {
            defaults.set(garbage, forKey: LastOpenedProject.key)
            #expect(remembered.id == nil)
        }
        remembered.id = nil
        #expect(defaults.object(forKey: LastOpenedProject.key) == nil)
    }

    @Test("a project ID reads back from its UUID string, and garbage reads as none")
    func projectIDStrings() {
        #expect(ProjectID(uuidString: Self.last.uuidString) == Self.last)
        #expect(ProjectID(uuidString: "not a uuid") == nil)
        #expect(ProjectID(uuidString: nil) == nil)
    }
}
