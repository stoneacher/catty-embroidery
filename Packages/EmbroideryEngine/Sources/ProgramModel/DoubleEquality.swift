extension Double {
    /// NaN-aware equality (Java `Double.equals` parity): NaN compares equal to
    /// NaN so that whole-model equality stays reflexive for ADR-006 assertions.
    /// Unlike Java, +0.0 and -0.0 stay equal — Swift `==` semantics.
    func isSameValue(as other: Double) -> Bool {
        self == other || (isNaN && other.isNaN)
    }
}
