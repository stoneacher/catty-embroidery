import Foundation

/// A design name the Tajima `LA` header field can carry **verbatim** — validated rather
/// than normalised, so that what the user typed is what the machine displays (US-308).
///
/// **This is a rejecting layer in front of a mangling backstop, and both are wanted.**
/// `DSTHeader.sanitized(_:)` already maps non-ASCII scalars to `_` and truncates to 15,
/// and it stays exactly as it is — pinned by `DSTHeaderTests.nameSanitization`, which
/// US-308 extended with the two rows this type's design reasons from: `"a/b:c"` reaching
/// the label untouched, and `"  pad  "` keeping its leading whitespace. The division of
/// labour:
///
/// - *Here*: input a **user** can see and fix is refused, and the reason names the count
///   or the offending character, so the field can say what is wrong while they type.
/// - *There*: input **no user typed** — an imported `.catrobat` project name, a future
///   CLI argument, an M5 project title — is silently normalised, so that no caller
///   anywhere can emit a 16-byte or non-ASCII `LA` field.
///
/// ADR-026 records why they are not collapsed into one. The short version: requiring a
/// `DesignName` in `DSTFile.init` would make the backstop unreachable and would ripple
/// through 56 call sites across 20 files, and the property worth keeping is precisely
/// that a direct engine caller *still* cannot produce a malformed label.
///
/// 15 is Catroid's limit and the `LA` field's width — **not** Catty's 16 (ADR-012).
public struct DesignName: Hashable, Sendable {
    /// The `LA` field's width, in characters. Equal to its width in bytes, because
    /// `validating(_:)` admits only printable ASCII before it measures length — see there.
    public static let maximumLength = 15

    /// The validated name: trimmed, non-empty, ASCII, at most 15 characters.
    public let value: String

    private init(unchecked value: String) {
        self.value = value
    }

    /// What both the validator and the field's live counter measure.
    ///
    /// Exposed so the view cannot invent a second definition: a counter over the raw
    /// string could read "16/15" while validation passed, or "15/15" while it failed.
    ///
    /// It trims, and that is a UX decision rather than tidiness — a trailing space is not
    /// going into the file, so it must not consume the user's budget.
    public static func normalised(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Validates `raw`, trimming leading and trailing whitespace first.
    ///
    /// Returns a `Result` rather than throwing because the app *renders* the problem
    /// beside the field on every keystroke; it does not catch it. Only the **first**
    /// violation is reported, in a fixed order, which is the same determinism ADR-025
    /// pins for the header's fields.
    ///
    /// **The order is `empty`, then the character rule, then length**, and the middle step
    /// is a UX decision worth stating: a 19-character name containing `ö` reports the `ö`,
    /// because that character can never be stored whatever the length, so reporting
    /// length first would have the user delete characters and fail again.
    ///
    /// Checking characters before length also earns the invariant this type advertises —
    /// but **only because the rule is printable ASCII rather than `Character.isASCII`**,
    /// which is the trap an in-loop review caught here. `Character.isASCII` is
    /// `asciiValue != nil`, and `asciiValue` **special-cases the `"\r\n"` grapheme cluster
    /// to `0x0A`** — so under that rule a "15-character" name measured **28 bytes**, the
    /// header truncated it to 15 *scalars*, and the type's "carried verbatim" promise was
    /// false in exactly the silent-truncation way this story exists to replace. Requiring
    /// every scalar to be printable makes 15 characters genuinely 15 bytes, which is the
    /// same argument `DSTHeader.sanitized` makes for mapping before truncating.
    ///
    /// Trimming happens before the length check, so 15 characters padded with spaces is
    /// valid rather than 17-and-too-long — otherwise the user is told to delete
    /// characters they cannot see.
    public static func validating(_ raw: String) -> Result<DesignName, DesignNameProblem> {
        let trimmed = normalised(raw)

        guard !trimmed.isEmpty else {
            // Covers the all-whitespace name too, which in the `LA` field would be
            // indistinguishable from an empty one.
            return .failure(.empty)
        }
        if let offender = trimmed.first(where: { !Self.isPrintableASCII($0) }) {
            return .failure(.unsupportedCharacter(offender))
        }
        guard trimmed.count <= maximumLength else {
            return .failure(.tooLong(count: trimmed.count, limit: maximumLength))
        }
        return .success(DesignName(unchecked: trimmed))
    }

    /// Every scalar in `0x20`–`0x7E`.
    ///
    /// **Every scalar, not `Character.isASCII`** — see `validating(_:)`. Checking the
    /// cluster's scalars is what rejects `"\r\n"`, which `isASCII` reports as a single
    /// ASCII character.
    private static func isPrintableASCII(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x20 ... 0x7E).contains($0.value) }
    }
}

/// Why a design name was refused (US-308).
///
/// Each case carries what the message needs to be specific, because the alternative is
/// the reference behaviour this story exists to replace: Catroid silently `take(15)`s the
/// name and mangles non-ASCII to `?` bytes under `US_ASCII`, telling the user nothing.
///
/// `Error` so callers may use `Result.get()`; the app reads the case directly and maps it
/// to a String Catalog entry, since ADR-011 keeps user-facing wording out of the package.
public enum DesignNameProblem: Error, Hashable, Sendable {
    /// Empty, or nothing but whitespace.
    case empty

    /// A character the `LA` field cannot carry: anything outside printable ASCII
    /// (`0x20`–`0x7E`).
    ///
    /// **Not named `nonASCII`, because that would be false.** `0x00`, `0x0A`, `0x1A` and
    /// `0x7F` are all ASCII and all refused — the middle two are the header's *own* field
    /// terminators, so a name containing them would corrupt the field structure a reader
    /// scans for, and `0x00` truncates any C string the value reaches.
    ///
    /// The payload is the **first** offender in reading order, so a user fixing them left
    /// to right sees progress. It is named rather than merely counted because the offender
    /// is usually invisible — a control character from a paste, a non-breaking space, or a
    /// smart quote the keyboard substituted for the one that was typed.
    case unsupportedCharacter(Character)

    /// `count` is the **trimmed** length, matching what `normalised(_:)` gives the
    /// counter, so the field cannot show one number while the error implies another.
    case tooLong(count: Int, limit: Int)
}
