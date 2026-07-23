import ProgramModel

/// The read side of a thread's variable resolution, backed by the interpreter's
/// mutable stores. Object variables shadow same-named project variables; an
/// unknown name resolves to 0 — the same rule as `ProgramModel.VariableScope`,
/// but over the live `[String: Double]` dictionaries the stepper writes to
/// (`setVariable` / `changeVariableBy`). Transient and synchronous: built per
/// formula evaluation from value-typed dictionary copies (COW keeps it cheap),
/// so it matches `Scope`'s deliberately non-`Sendable` contract.
struct VariableStoreScope: Scope {
    let objectVariables: [String: Double]
    let projectVariables: [String: Double]

    func value(of variableName: String) -> Double {
        objectVariables[variableName] ?? projectVariables[variableName] ?? 0
    }
}
