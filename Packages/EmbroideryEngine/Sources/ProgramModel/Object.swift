/// A programmable actor (Catroid `Sprite.java`). Scripts land in US-203; this is
/// the script-free spine. Positions are plain `Double`s in stage coordinates —
/// ADR-007: center origin, y-up, heading in degrees with 0° = up — converted to
/// engine `StagePoint`s by the interpreter, which also maps each object to an
/// `ActorID` and `zIndex` to the engine `layer`.
public struct Object: Sendable, Equatable, Codable {
    public var name: String
    public var startX: Double
    public var startY: Double
    public var startHeading: Double
    public var zIndex: Int
    /// Object-scoped variables; shadow same-named project-scoped ones.
    public var variables: [Variable]

    public init(
        name: String = "",
        startX: Double = 0,
        startY: Double = 0,
        startHeading: Double = 0,
        zIndex: Int = 0,
        variables: [Variable] = []
    ) {
        self.name = name
        self.startX = startX
        self.startY = startY
        self.startHeading = startHeading
        self.zIndex = zIndex
        self.variables = variables
    }
}
