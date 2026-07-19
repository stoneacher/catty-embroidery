/// Formula evaluation failure (Catroid `InterpretationException` raised via
/// `assertNotNaN`): a NaN result at the root is the only throw condition —
/// per-node normalization already caps ±∞, so nothing else can fail. US-205
/// brick execution catches this and falls back instead of aborting the program.
public enum FormulaError: Error, Equatable, Sendable {
    case notANumber
}
