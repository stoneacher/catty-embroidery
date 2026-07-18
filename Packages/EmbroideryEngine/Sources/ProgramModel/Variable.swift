/// A named numeric variable (Catroid `UserVariable`). The M2 formula subset is
/// numeric-only, so the value is a `Double`; name uniqueness within a scope is
/// enforced by the editor/interpreter, not the model.
///
/// Non-finite values: the US-202 formula semantics let ±∞ reach a variable at
/// runtime, and the default `JSONEncoder` throws on non-finite doubles — the M5
/// persistence layer must pin a policy (non-conforming-float strategy or clamp)
/// before programs are saved.
public struct Variable: Sendable, Equatable, Codable {
    public var name: String
    public var value: Double

    public init(name: String, value: Double = 0) {
        self.name = name
        self.value = value
    }
}
