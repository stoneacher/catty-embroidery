/// One reason a `code.xml` cannot be imported (language-test runner brief, D7).
///
/// The importer collects every blocker it meets rather than stopping at the first,
/// so the runner can say what a test needs. Cases are added slice by slice.
package enum ImportBlocker: Error, Hashable, Sendable {
    /// The data is not well-formed XML.
    case malformed
    /// An XStream `reference=` path that leads nowhere, or to another reference.
    case unresolvedReference(String)
    /// A formula element type outside the supported subset, e.g. `USER_LIST`.
    case elementType(String)
    /// A `FUNCTION` name `Formula` has no case for, e.g. `JOIN` or `RAND`.
    case function(String)
    /// A `SENSOR` name `Formula` has no case for, e.g. `TIMER`.
    case sensor(String)
    /// An `OPERATOR` name `Formula` has no case for, e.g. Catroid's dead `MOD`.
    case operatorName(String)
    /// A literal that would be compared or stored as a string (brief D4).
    case stringValue(StringContext)
    /// A literal Java parses to ±∞; Catroid keeps its raw string (brief D4).
    case nonFiniteLiteral(String)
    /// A formula node whose children do not fit its type or operator.
    case formulaShape(String)
    /// A formula deeper than `FormulaImport.maximumDepth` (ADR-037's cap).
    case formulaTooDeep
    /// A `catrobatLanguageVersion` outside brief D1's window, as written.
    case version(String)
    /// More than one scene; Catroid plays one.
    case multipleScenes
    /// A brick type with no mapping, e.g. `BroadcastBrick`.
    case brick(String)
    /// A script type other than StartScript or EmptyScript.
    case script(String)
    /// A program-level element the import has no counterpart for.
    case element(String)
    /// A supported brick missing a part it needs, or with one it cannot map.
    case brickShape(String)
    /// A name declared by an object and by the project (brief D7).
    case variableShadowing(String)
    /// A variable a SetVariable stores as a Boolean or string, and that is then
    /// changed or looped over (brief D4).
    case variableStorage(String)
    /// `ImportedProgram.program()` met an AssertEquals, FinishStage, ExitStage or
    /// WaitTillIdle, which have no `Brick` case (brief D3).
    case harnessStep
}

/// Where a string literal would keep its string meaning in Catroid (brief D4).
package enum StringContext: Hashable, Sendable {
    /// An operand of `=` or `≠`.
    case equality
    /// An operand of AssertEquals.
    case assertOperand
    /// The value a SetVariable stores.
    case variableValue
}
