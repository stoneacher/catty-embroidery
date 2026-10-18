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

extension VirtualNeedle {
    /// The heading as Catroid's `MOTION_DIRECTION` reports it, folded into
    /// (−180, 180] (`Look.breakDownCatroidAngle`). The needle itself keeps its
    /// exact mod-360 representation (ADR-014); the fold happens only at the read.
    var catroidDirection: Double {
        let reduced = heading.truncatingRemainder(dividingBy: 360)
        if reduced > 180 {
            return reduced - 360
        }
        if reduced <= -180 {
            return reduced + 360
        }
        return reduced
    }
}
