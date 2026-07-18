/// Root of the pure value graph (ADR-016): a program is scenes plus
/// project-scoped variables, mirroring Catroid's `Project` (`Project.java`:
/// `sceneList`, `userVariables`). Holds no engine types — the interpreter owns
/// every model↔engine conversion.
public struct Program: Sendable, Equatable, Codable {
    /// Version of the serialized format (ADR-003), stamped so later milestones
    /// can migrate old files.
    public static let currentFormatVersion: Int = 1

    public var formatVersion: Int
    public var name: String
    public var scenes: [Scene]
    /// Project-scoped variables; object-scoped ones (on `Object`) shadow
    /// same-named entries here (Catroid sprite-first-then-project resolution).
    public var variables: [Variable]

    public init(
        formatVersion: Int = Program.currentFormatVersion,
        name: String = "",
        scenes: [Scene] = [],
        variables: [Variable] = []
    ) {
        self.formatVersion = formatVersion
        self.name = name
        self.scenes = scenes
        self.variables = variables
    }
}
