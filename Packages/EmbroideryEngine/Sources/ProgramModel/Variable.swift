/// A named numeric variable (Catroid `UserVariable`). The M2 formula subset is
/// numeric-only, so the value is a `Double`; name uniqueness within a scope is
/// enforced by the editor/interpreter, not the model.
///
/// Non-finite values: the US-202 formula semantics let ±∞ reach a variable at
/// runtime, and the default `JSONEncoder` throws on non-finite doubles. ADR-037
/// (US-404) pins the policy: no float strategy and no clamp. The runtime value
/// lives in the interpreter's own stores and never reaches this model (executed
/// by `RuntimeVariableIsolationTests`), so any future runtime → model write-back
/// must pass the same finite check the number pad does, or be refused.
public struct Variable: Sendable, Equatable, Codable {
    public var name: String
    public var value: Double

    public init(name: String, value: Double = 0) {
        self.name = name
        self.value = value
    }

    /// NaN-valued variables compare equal, keeping whole-`Program` equality
    /// reflexive for ADR-006 assertions (Catroid parity: `UserVariable.equals`
    /// is identity-true and Java `Double.equals` treats NaN as equal).
    public static func == (lhs: Variable, rhs: Variable) -> Bool {
        lhs.name == rhs.name && lhs.value.isSameValue(as: rhs.value)
    }
}
