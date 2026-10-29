#if DEBUG
    import Foundation

    /// US-316's result lines, appended to a file in the app's container as well as emitted to the
    /// trace and the console.
    ///
    /// **Because the trace alone lost one.** The `result` Points-of-Interest event of a hand run
    /// never reached its trace (2026-10-29), as a `capture` Begin had not on two others, so a
    /// capsule's numbers need a home that does not depend on the signpost channel. The file is
    /// pulled after a run with `xcrun devicectl device copy from … --domain-type
    /// appDataContainer … --source Library/Caches/US316-results.txt` (us316-device-handoff.md).
    enum CaptureResultLog {
        static let fileName = "US316-results.txt"

        /// The app's Caches directory, where a run's lines go.
        static var defaultDirectory: URL {
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        }

        /// Appends `line` and a newline, creating the file if needed.
        static func append(_ line: String, in directory: URL = defaultDirectory) throws {
            let url = directory.appendingPathComponent(fileName)
            let data = Data((line + "\n").utf8)
            guard FileManager.default.fileExists(atPath: url.path) else {
                try data.write(to: url)
                return
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        }
    }
#endif
