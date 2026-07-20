/// A programmable actor (Catroid `Sprite.java`). Positions are plain `Double`s in
/// stage coordinates — ADR-007: center origin, y-up, heading in degrees with
/// 0° = up — converted to engine `StagePoint`s by the interpreter, which also
/// maps each object to an `ActorID` and `zIndex` to the engine `layer`.
public struct Object: Sendable, Equatable, Codable {
    public var name: String
    public var startX: Double
    public var startY: Double
    public var startHeading: Double
    public var zIndex: Int
    /// Object-scoped variables; shadow same-named project-scoped ones.
    public var variables: [Variable]
    /// The object's scripts (Catroid `Sprite.scriptList`). Deferred from US-201
    /// to US-203 so it lands alongside the `Script`/`Brick` types it contains.
    public var scripts: [Script]

    public init(
        name: String = "",
        startX: Double = 0,
        startY: Double = 0,
        startHeading: Double = 0,
        zIndex: Int = 0,
        variables: [Variable] = [],
        scripts: [Script] = []
    ) {
        self.name = name
        self.startX = startX
        self.startY = startY
        self.startHeading = startHeading
        self.zIndex = zIndex
        self.variables = variables
        self.scripts = scripts
    }

    /// NaN-aware on the `Double` fields for the same reflexivity guarantee as
    /// `Variable.==` — every `Double` reachable from `Program` compares NaN-equal.
    public static func == (lhs: Object, rhs: Object) -> Bool {
        lhs.name == rhs.name
            && lhs.startX.isSameValue(as: rhs.startX)
            && lhs.startY.isSameValue(as: rhs.startY)
            && lhs.startHeading.isSameValue(as: rhs.startHeading)
            && lhs.zIndex == rhs.zIndex
            && lhs.variables == rhs.variables
            && lhs.scripts == rhs.scripts
    }
}
