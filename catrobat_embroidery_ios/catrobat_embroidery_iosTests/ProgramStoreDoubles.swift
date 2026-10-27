@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Projects

// Doubles for the persistence seam (US-406), shared by the autosave suites and by every suite
// that only needs an `AppModel` to exist.
//
// Free types, as in `ExportDoubles.swift`. Each test builds its own instance, so parallel
// execution shares no mutable state.

/// Holds the saved program in memory and records every write.
@MainActor
final class InMemoryProgramStore: ProgramStoring {
    struct Failure: Error {}

    /// What is "on disk".
    var stored: Program?
    /// Every program written, in order. A dropped save never reaches the store, so it never
    /// appears here.
    private(set) var saves: [Program] = []
    private(set) var loadCount = 0
    private(set) var setAsideCount = 0
    private(set) var removeCount = 0

    /// When set, `load()` throws it instead of reading `stored`.
    var loadError: ProgramLoadError?
    /// When `true`, `save(_:)` throws and leaves `stored` alone.
    var failsSaves = false
    /// When `true`, `remove()` throws and leaves the file where it is.
    var failsRemove = false

    init(stored: Program? = nil) {
        self.stored = stored
    }

    func load() throws(ProgramLoadError) -> Program? {
        loadCount += 1
        if let loadError {
            throw loadError
        }
        return stored
    }

    func save(_ program: Program) throws {
        if failsSaves {
            throw Failure()
        }
        stored = program
        saves.append(program)
    }

    func remove() throws {
        if failsRemove {
            throw Failure()
        }
        removeCount += 1
        loadError = nil
        stored = nil
    }

    func setAside() throws -> URL {
        setAsideCount += 1
        loadError = nil
        stored = nil
        return URL.temporaryDirectory.appending(path: "set-aside-\(setAsideCount).json")
    }
}

/// A per-test directory under the system temporary directory, removed afterwards —
/// `TemporaryDSTFileWriterTests`' arrangement, since a fixed path would be shared mutable state
/// under parallel execution.
func inDisposableDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = URL.temporaryDirectory.appending(path: "program-store-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
}
