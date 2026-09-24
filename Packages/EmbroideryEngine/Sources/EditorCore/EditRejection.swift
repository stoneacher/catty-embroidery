import ProgramModel

/// Which hop of a `BrickAddress` failed to resolve.
///
/// A `BrickAddress` has four independently-resolvable components, so "out of
/// bounds" without a discriminator is ambiguous — and, more practically, a
/// single collapsed `guard` over all four hops would satisfy any test that only
/// asked whether *some* rejection came back. Naming the hop makes each bounds
/// check individually discriminating.
public enum AddressComponent: Sendable, Equatable, CaseIterable {
    case scene
    case object
    case script
    case brick
}

/// Why an `EditAction` was refused.
///
/// `Equatable` and `Sendable` so a call site can assert the exact reason in one
/// line, which is the second of ADR-033's three arguments for returning a
/// rejection instead of throwing.
///
/// ## Why some failures have one spelling and one has two
///
/// `ScriptMoveError` already names four failures, and three of them overlap with
/// cases here. The overlap is resolved by **guarding before delegating**, so each
/// failure has exactly one spelling:
///
/// - `sourceOutOfBounds` — unreachable. `apply` must bounds-check the source
///   before it can read the brick that decides opener/`loopEnd`/leaf, so
///   `.addressOutOfBounds(.brick, …)` always wins the race.
/// - `sourceIsNotLoopOpener` — unreachable. `movingPair` is only called once
///   `opensLoop` is already true.
/// - `destinationOutOfBounds` — **normalised** to this type's own case. The pair
///   path learns the bound from `movingPair` and the leaf path computes it in
///   `EditorCore`; without normalisation the same user-visible failure would
///   acquire two spellings selected by what kind of brick the source happened to
///   be. The accepted cost is that the bound `0 ... (count − span)` now exists in
///   two places, which `EditMoveTests.destinationBoundsAgree` pins rather than a
///   comment.
/// - `unbalancedPair` — **wrapped**, and the only `ScriptMoveError` `apply` can
///   actually return. ADR-008 owns that rule and ADR-033 requires it keep exactly
///   one definition, so it is carried through rather than restated.
public enum EditRejection: Equatable, Sendable {
    /// The address did not resolve; the component says which hop.
    case addressOutOfBounds(AddressComponent, at: BrickAddress)

    /// A `move` destination outside `0 ... (bricks.count − span)`.
    case destinationOutOfBounds(index: Int)

    /// `insert(.loopEnd, …)`. Refusing to mint a bare `loopEnd` is what makes
    /// milestone exit criterion 4 provable rather than merely tested (ADR-035).
    ///
    /// Payload-free, and checked **before** the address resolves: the rule is the
    /// kind, not the place, so `insert(.loopEnd, …)` answers the same thing
    /// wherever it is aimed.
    case cannotInsertLoopEnd

    /// `move(from:)` a `loopEnd` — the one move that can split a pair.
    case cannotMoveLoopEnd(at: BrickAddress)

    /// `replaceBrick` with a different kind. `from` is the brick that is there,
    /// `to` the replacement that was offered.
    case cannotChangeBrickKind(from: BrickKind, to: BrickKind)

    /// A move rule that `ProgramModel` owns (ADR-008), carried through rather
    /// than restated. In practice this is always `.unbalancedPair` — see the
    /// type's documentation.
    case scriptMove(ScriptMoveError)
}

/// The outcome of `EditorCore.apply(_:to:)`: a new program, or a reason.
///
/// Not `Result<Program, EditRejection>`, deliberately — a named type keeps the
/// rejection from reading as an *error* at call sites that branch on it as
/// ordinary control flow, which ADR-033 says every one of them does.
public enum EditResult: Equatable, Sendable {
    case applied(Program)
    case rejected(EditRejection)
}
