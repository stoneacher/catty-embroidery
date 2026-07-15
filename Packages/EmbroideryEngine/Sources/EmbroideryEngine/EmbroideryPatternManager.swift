/// Stubs for the US-110 red phase — the Catroid `DSTPatternManager` port
/// lands with the green phase.
public struct ActorID: Hashable, Sendable {
    public let rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }
}

public struct EmbroideryPatternManager: Sendable {
    public init() {}

    public var hasValidPattern: Bool {
        false
    }

    public mutating func setThreadColor(_: ThreadColor, for _: ActorID) {}

    public mutating func setThreadColor(hexString _: String, for _: ActorID) {}

    public mutating func addStitch(at _: StagePoint, layer _: Int, actor _: ActorID) {}

    public func assembled() -> EmbroideryStream {
        EmbroideryStream()
    }
}
