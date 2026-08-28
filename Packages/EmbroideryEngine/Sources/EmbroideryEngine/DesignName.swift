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
    /// `validating(_:)` rejects non-ASCII before it measures length — see there.
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
    /// **The order is `empty`, then ASCII, then length**, and the middle step is a UX
    /// decision worth stating: a 19-character name containing `ö` reports the `ö`,
    /// because that character can never be stored whatever the length, so reporting
    /// length first would have the user delete characters and fail again.
    ///
    /// Checking ASCII before length also earns the invariant this type advertises:
    /// once every `Character` is a single ASCII scalar, 15 characters *are* 15 bytes, so
    /// `maximumLength` is simultaneously a character and a byte bound. That is the same
    /// argument `DSTHeader.sanitized` makes for mapping before truncating, and it is why
    /// the two steps cannot be swapped here either.
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
        if let offender = trimmed.first(where: { !$0.isASCII }) {
            return .failure(.nonASCII(character: offender))
        }
        guard trimmed.count <= maximumLength else {
            return .failure(.tooLong(count: trimmed.count, limit: maximumLength))
        }
        return .success(DesignName(unchecked: trimmed))
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

    /// `character` is the **first** non-ASCII character in reading order, so a user
    /// fixing them left to right sees progress. It is named rather than merely counted
    /// because the offender is often invisible — a combining accent, a non-breaking
    /// space, or a smart quote the keyboard substituted for the one that was typed.
    case nonASCII(character: Character)

    /// `count` is the **trimmed** length, matching what `normalised(_:)` gives the
    /// counter, so the field cannot show one number while the error implies another.
    case tooLong(count: Int, limit: Int)
}
