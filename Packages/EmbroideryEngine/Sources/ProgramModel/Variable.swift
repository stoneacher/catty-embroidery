/// A named numeric variable (Catroid `UserVariable`). The M2 formula subset is
/// numeric-only, so the value is a `Double`; name uniqueness within a scope is
/// enforced by the editor/interpreter, not the model.
public struct Variable: Sendable, Equatable, Codable {
    public var name: String
    public var value: Double

    public init(name: String, value: Double = 0) {
        self.name = name
        self.value = value
    }
}
