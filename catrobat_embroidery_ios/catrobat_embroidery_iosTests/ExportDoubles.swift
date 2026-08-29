@testable import catrobat_embroidery_ios
import EmbroideryEngine
import Foundation

// Doubles for the export seam, shared by `ExportViewModelTests` and `ExportWiringTests`.
//
// Free types rather than suite members, matching `RunDriving`'s arrangement in the package
// tests — and so that no one suite's `type_body_length` pays for them. Each test builds its
// own instance, so parallel execution shares no mutable state.

/// Records what it was asked to write instead of touching the filesystem.
///
/// Catty's `EmbroideryServiceMock` shape, which is the one thing in that file worth porting:
/// the injected seam is what lets the whole export path be exercised without a disk.
@MainActor
final class RecordingDSTFileWriter: DSTFileWriting {
    struct Write: Equatable {
        var file: DSTFile
        var name: DSTFileName
        var url: URL
    }

    private(set) var written: [Write] = []
    private(set) var removeAllCount = 0

    func write(_ file: DSTFile, named name: DSTFileName) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "recorded/\(name.value)")
        written.append(Write(file: file, name: name, url: url))
        return url
    }

    func removeAll() {
        removeAllCount += 1
    }
}

/// Fails every write, for the "the design stays on screen" half of test item 3.
@MainActor
final class ThrowingDSTFileWriter: DSTFileWriting {
    struct Failure: Error {}

    func write(_: DSTFile, named _: DSTFileName) throws -> URL {
        throw Failure()
    }

    func removeAll() {}
}
