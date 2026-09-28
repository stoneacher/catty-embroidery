@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel

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

    /// When set, `load()` throws it instead of reading `stored`.
    var loadError: ProgramLoadError?
    /// When `true`, `save(_:)` throws and leaves `stored` alone.
    var failsSaves = false

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

    func setAside() throws -> URL {
        setAsideCount += 1
        loadError = nil
        stored = nil
        return URL.temporaryDirectory.appending(path: "set-aside-\(setAsideCount).json")
    }
}

/// The real store on a real disk, except that setting a file aside fails until told otherwise.
///
/// A read-only directory cannot stand in for this: it fails the atomic write as well as the
/// rename (probed at planning, both `NSCocoaError` 513), so a real-disk version of "the blank
/// program must not overwrite an unpreserved file" would pass because *nothing* can write.
@MainActor
final class SetAsideFailingStore: ProgramStoring {
    struct Failure: Error {}

    private let wrapped: DocumentsProgramStore
    var setAsideFails = true

    init(wrapping wrapped: DocumentsProgramStore) {
        self.wrapped = wrapped
    }

    func load() throws(ProgramLoadError) -> Program? {
        try wrapped.load()
    }

    func save(_ program: Program) throws {
        try wrapped.save(program)
    }

    func setAside() throws -> URL {
        if setAsideFails {
            throw Failure()
        }
        return try wrapped.setAside()
    }
}

extension ProgramAutosave {
    /// An autosave nothing will ever look at, for suites that need an `AppModel` and do not
    /// test persistence.
    static func inMemory() -> ProgramAutosave {
        ProgramAutosave(store: InMemoryProgramStore())
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

/// The files in `directory` other than the working program, with their bytes.
func setAsideFiles(in directory: URL) throws -> [Data] {
    try FileManager.default
        .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent != "WorkingProgram.json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { try Data(contentsOf: $0) }
}

/// Stored-file fixtures the codec refuses, each for a different reason.
enum RefusedDocument {
    /// A well-formed file from a later format.
    static var futureVersion: Data {
        get throws {
            try JSONEncoder().encode(Program(formatVersion: 2, name: "from the future"))
        }
    }

    /// Not JSON at all.
    static let corrupt = Data("{".utf8)

    /// A version-1 file that parses and fails only on balance: a bare `loopEnd`, which the
    /// editor can never produce but a hand edit can.
    static var unbalanced: Data {
        get throws {
            try JSONEncoder().encode(
                Program(
                    name: "hand-edited",
                    scenes: [Scene(objects: [Object(scripts: [Script(bricks: [.loopEnd])])])]
                )
            )
        }
    }
}
