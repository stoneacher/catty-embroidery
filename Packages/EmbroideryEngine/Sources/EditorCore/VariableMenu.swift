import ProgramModel

/// The variables a formula in one object can reference (US-410).
public struct VariableMenu: Sendable, Equatable {
    public enum Scope: Sendable, Equatable {
        case object
        case project
    }

    public let objectVariables: [String]
    public let projectVariables: [String]

    public init(program _: Program, script _: ScriptAddress) {
        objectVariables = []
        projectVariables = []
    }

    public var names: [String] {
        []
    }

    public func scope(of _: String) -> Scope? {
        nil
    }
}
