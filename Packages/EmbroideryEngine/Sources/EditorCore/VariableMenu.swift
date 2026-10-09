import ProgramModel

/// The variables a formula in one object can reference (US-410), in the order
/// the interpreter resolves them: the object's own first, then the project's,
/// first match by name (`VariableScope.value(of:)`).
///
/// A name is listed **once**. A project variable shadowed by an object one is
/// left out, since choosing it would produce a `.variable` the interpreter
/// resolves to the object's anyway; a repeated name in one scope — which the
/// model permits and this editor no longer creates — is listed at its first
/// occurrence, the one that wins.
public struct VariableMenu: Sendable, Equatable {
    /// Which scope a listed name resolves in.
    public enum Scope: Sendable, Equatable {
        case object
        case project
    }

    public let objectVariables: [String]
    public let projectVariables: [String]

    /// Total, like `EditorCore.apply`: a `script` that does not resolve offers
    /// the project's variables only.
    public init(program: Program, script: ScriptAddress) {
        var object: [Variable] = []
        if program.scenes.indices.contains(script.sceneIndex) {
            let objects = program.scenes[script.sceneIndex].objects
            if objects.indices.contains(script.objectIndex) {
                object = objects[script.objectIndex].variables
            }
        }
        let objectNames = Self.uniqued(object.map(\.name))
        objectVariables = objectNames
        projectVariables = Self.uniqued(program.variables.map(\.name)).filter { !objectNames.contains($0) }
    }

    /// Every listed name, object scope first.
    public var names: [String] {
        objectVariables + projectVariables
    }

    /// Where `name` resolves, or `nil` when nothing declares it.
    public func scope(of name: String) -> Scope? {
        if objectVariables.contains(name) {
            return .object
        }
        if projectVariables.contains(name) {
            return .project
        }
        return nil
    }

    private static func uniqued(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        return names.filter { seen.insert($0).inserted }
    }
}
