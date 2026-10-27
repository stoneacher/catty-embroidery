@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Projects

// Doubles for the project seam (project management slice 4), as `ProgramStoreDoubles.swift`
// is for M4's single file. Free types; each test builds its own instance. Since US-329 the
// `Projects` package's own suites keep fuller copies; these are the ones the app's
// `AppModel` suites use (a shared test-support target would need a pbxproj change).

/// Holds the projects in memory and records every write and delete.
@MainActor
final class InMemoryProjectStore: ProjectStoring {
    struct Failure: Error {}

    /// What is "on disk": a program, or a file that refuses with a reason and maybe a name.
    enum Entry: Equatable {
        case program(Program)
        case refused(ProgramDocumentError, name: String?)
        /// A file that exists but cannot be read at all.
        case unreadable
    }

    var entries: [ProjectID: Entry]
    /// Every write, in order; a dropped or blocked save never appears.
    private(set) var saves: [(id: ProjectID, program: Program)] = []
    private(set) var deletes: [ProjectID] = []
    private(set) var listCount = 0

    /// IDs whose saves throw and leave the entry alone.
    var failingSaves: Set<ProjectID> = []
    /// When `true`, every save throws, including one to an ID not yet known (a duplicate's).
    var failsEverySave = false
    /// When `true`, `delete(_:)` throws and leaves the entry alone.
    var failsDeletes = false

    /// The date every listed file carries.
    var modified = Date(timeIntervalSince1970: 1_700_000_000)

    init(_ entries: [ProjectID: Entry] = [:]) {
        self.entries = entries
    }

    func program(_ id: ProjectID) -> Program? {
        if case let .program(program) = entries[id] {
            program
        } else {
            nil
        }
    }

    func load(_ id: ProjectID) throws(ProgramLoadError) -> Program? {
        switch entries[id] {
        case nil: nil
        case let .program(program): program
        case let .refused(reason, _): throw .document(reason)
        case .unreadable: throw .unreadable
        }
    }

    func save(_ program: Program, as id: ProjectID) throws {
        if failsEverySave || failingSaves.contains(id) {
            throw Failure()
        }
        entries[id] = .program(program)
        saves.append((id, program))
    }

    func delete(_ id: ProjectID) throws {
        if failsDeletes {
            throw Failure()
        }
        entries[id] = nil
        deletes.append(id)
    }

    /// Unknown, so the library falls back to its injected clock, which the tests pin.
    func modified(_: ProjectID) -> Date? {
        nil
    }

    func list() throws -> [ProjectFile] {
        listCount += 1
        return entries.map { id, entry in
            switch entry {
            case let .program(program):
                ProjectFile(id: id, inspection: .openable(program), modified: modified)
            case let .refused(reason, name):
                ProjectFile(id: id, inspection: .refused(reason, name: name), modified: modified)
            case .unreadable:
                ProjectFile(id: id, inspection: .refused(.corrupt, name: nil), modified: modified)
            }
        }
    }
}

extension ProjectID {
    /// A fixed ID for tests, `00000000-0000-0000-0000-<n>`.
    static func fixed(_ number: Int) -> ProjectID {
        ProjectID(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!)
    }
}

extension LastOpenedProject {
    /// Over a defaults suite of its own, so no test reads or writes the app's defaults.
    static func disposable() -> LastOpenedProject {
        LastOpenedProject(defaults: UserDefaults(suiteName: "last-opened-\(UUID().uuidString)")!)
    }
}

extension ProjectLibrary {
    /// A library nothing will ever look at, for suites that need an `AppModel` and do not test
    /// persistence.
    static func inMemory() -> ProjectLibrary {
        ProjectLibrary(store: InMemoryProjectStore(), lastOpened: .disposable())
    }
}
