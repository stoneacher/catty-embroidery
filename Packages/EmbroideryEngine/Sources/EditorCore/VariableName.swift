/// The rules a variable name must satisfy (US-410).
public enum VariableName {
    public static func validate(_: String) -> Result<String, VariableNameProblem> {
        .failure(.empty)
    }
}

/// Which rule a variable name broke.
public enum VariableNameProblem: Error, Sendable, Equatable {
    case empty
    case surroundingWhitespace
    case controlCharacter
    case quotationMark
    case leadingOpenPunctuation
}
