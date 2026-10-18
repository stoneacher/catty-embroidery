/// What a formula reads while it evaluates: variables (the read half of Catroid
/// `UserDataWrapper.java`) and, from ADR-046, the acting object's sensors.
/// Deliberately NOT `Sendable`-constrained: US-205's
/// interpreter backs it with a mutable variable store.
public protocol Scope {
    /// The current value of the named variable; unknown names resolve to 0.
    func value(of variableName: String) -> Double

    /// The acting object's value for `sensor` (ADR-046). Required, with no
    /// default, so every scope decides what a sensor means where it lives: the
    /// interpreter's reads its needle, and `VariableScope`, which has none,
    /// answers 0 as Catroid does for unknown data.
    func value(of sensor: Sensor) -> Double
}

/// Immutable two-level scope over `Variable` collections (Catroid
/// `UserDataWrapper.getUserVariable`): object (sprite) scope is consulted
/// first, then project scope; an unknown name yields 0 (Catroid
/// `Conversions.FALSE`). Within each collection, the first match by name wins —
/// name uniqueness is the editor's job, not the model's.
public struct VariableScope: Scope, Sendable {
    private let objectVariables: [Variable]
    private let projectVariables: [Variable]

    public init(objectVariables: [Variable] = [], projectVariables: [Variable] = []) {
        self.objectVariables = objectVariables
        self.projectVariables = projectVariables
    }

    public func value(of variableName: String) -> Double {
        if let match = objectVariables.first(where: { $0.name == variableName }) {
            return match.value
        }
        if let match = projectVariables.first(where: { $0.name == variableName }) {
            return match.value
        }
        return 0
    }

    /// The model has no needle, so every sensor reads 0 (Catroid's value for
    /// unknown data, `Conversions.FALSE`). The interpreter's scope reads the
    /// real needle.
    public func value(of _: Sensor) -> Double {
        0
    }
}
