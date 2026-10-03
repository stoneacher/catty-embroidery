import ProgramModel

/// One editable value of a brick, named by what it means in the brick's
/// sentence (US-410).
public enum ParameterSlot: Sendable, Hashable, CaseIterable {
    case steps
    case degrees
    case x
    case y
    case times
    case seconds
    case value
    case length
    case width
    case variableName
    case hex
    case fileName
}

/// What a slot holds.
public enum ParameterValue: Sendable, Equatable {
    case formula(Formula)
    case variableName(String)
    case threadColor(hex: String)
    case fileName(String)
}

/// A slot and its current value.
public struct BrickParameter: Sendable, Equatable {
    public let slot: ParameterSlot
    public let value: ParameterValue

    public init(slot: ParameterSlot, value: ParameterValue) {
        self.slot = slot
        self.value = value
    }
}

public extension Brick {
    /// The brick's parameters in sentence order.
    var parameters: [BrickParameter] {
        []
    }

    /// The brick with one slot replaced.
    func replacing(_: ParameterSlot, with _: ParameterValue) -> Brick? {
        nil
    }
}
