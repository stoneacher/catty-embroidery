@testable import catrobat_embroidery_ios
import Foundation
import Testing

/// US-316's result lines also go to a file in the app's container, pulled with `devicectl`
/// after a run: the signpost channel dropped a hand run's result event (2026-10-29), so the
/// trace cannot be the only place a capsule's numbers live.
struct CaptureResultLogTests {
    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureResultLogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("lines are appended, one per line, in order")
    func appends() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try CaptureResultLog.append("US316 condition=A0 first", in: directory)
        try CaptureResultLog.append("US316 condition=A0 hand second", in: directory)

        let text = try String(contentsOf: directory.appendingPathComponent(CaptureResultLog.fileName), encoding: .utf8)
        #expect(text == "US316 condition=A0 first\nUS316 condition=A0 hand second\n")
    }

    @Test("the file name is the one the hand-off pulls")
    func fileName() {
        #expect(CaptureResultLog.fileName == "US316-results.txt")
    }
}
