import Foundation
import ProgramModel

/// What a project file holds, as the project list needs it (project management, brief D11):
/// a program to open, or the reason it cannot be opened together with whatever name a probe
/// could still read, so a refused file is listed by name rather than hidden.
public enum DocumentInspection: Equatable, Sendable {
    case openable(Program)
    case refused(ProgramDocumentError, name: String?)
}

public extension ProgramDocument {
    /// `data` read without throwing: `.openable` exactly when `decode` succeeds, otherwise
    /// `decode`'s own reason. The name comes from a probe that ignores every other key, so a
    /// newer format or a malformed body still shows the name its author gave it.
    static func inspect(_ data: Data) -> DocumentInspection {
        do {
            return try .openable(decode(data))
        } catch {
            return .refused(error, name: try? JSONDecoder().decode(NameProbe.self, from: data).name)
        }
    }
}

private struct NameProbe: Decodable {
    let name: String
}
