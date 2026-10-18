import ProgramModel

/// The read side of a thread's formula evaluation: variables backed by the
/// interpreter's mutable stores, and sensors backed by the acting object's needle
/// (ADR-046). Object variables shadow same-named project variables; an
/// unknown name resolves to 0 — the same rule as `ProgramModel.VariableScope`,
/// but over the live `[String: Double]` dictionaries the stepper writes to
/// (`setVariable` / `changeVariableBy`). Transient and synchronous: built per
/// formula evaluation from value-typed dictionary copies (COW keeps it cheap),
/// so it matches `Scope`'s deliberately non-`Sendable` contract.
struct VariableStoreScope: Scope {
    let objectVariables: [String: Double]
    let projectVariables: [String: Double]
    /// The acting object's needle when the scope was built, i.e. before the brick
    /// that evaluates through it applies (ADR-046).
    let needle: VirtualNeedle

    func value(of variableName: String) -> Double {
        objectVariables[variableName] ?? projectVariables[variableName] ?? 0
    }

    func value(of sensor: Sensor) -> Double {
        switch sensor {
        case .objectX: needle.position.x
        case .objectY: needle.position.y
        case .motionDirection: needle.catroidDirection
        }
    }
}
