import Foundation

/// The name of a `.dst` file on disk — **not** the header label (US-308).
///
/// They are unrelated fields in the format, and keeping them unrelated is this type's
/// whole reason to exist separately from `DesignName`. The label's rules come from the
/// fixed-width `LA` field; these come from the filesystem, and all four were measured
/// against a real write rather than inferred:
///
/// | input | result |
/// |---|---|
/// | `a/b.dst` | `/` is a path separator — `lastPathComponent` becomes `b.dst`, write fails NSError 4 |
/// | `.dst` (empty stem) | collapses to the directory, write fails NSError 512 |
/// | `a\0b.dst` | fails NSError 4, path truncated at the NUL — the probe's error named a file "T" |
/// | 264 characters | fails NSError 514, "file name is invalid" — a 255-byte `NAME_MAX` |
///
/// Measured **legal**, and therefore deliberately accepted: `Ünïcödé.dst`, `con:x.dst`,
/// `a\u{7F}b.dst`, `a\nb.dst`. The first row is the important one — the file name may
/// keep characters the header label cannot, which is exactly the independence US-308
/// asks for and which Catroid's `sanitizeFileName` does not provide (it has no empty
/// check at all, and produces a file literally named `.dst`).
///
/// Whitespace trimming is shared with `DesignName`. That is one sensible rule applied
/// twice rather than a dependency between the two types: nothing here consults
/// `DesignName`, and `DSTFileNameTests` asserts a `/` accepted by the label and refused
/// here to keep it that way.
public struct DSTFileName: Hashable, Sendable {
    /// Lowercase, and the only extension this type produces. Machines and desktop
    /// software accept either case — the exported UTType declares both `dst` and `DST`
    /// as filename tags — but what *we* write is one thing, not two.
    public static let fileExtension = "dst"

    /// `NAME_MAX`: 255 **bytes**, extension included, so the longest legal ASCII stem is
    /// 251 characters. Bytes rather than characters is load-bearing — 126 `ü` is 126
    /// characters and 252 bytes, and would slip past a character-based cap.
    public static let maximumByteLength = 255

    /// The validated stem, without the extension.
    public let stem: String

    /// The full file name, extension included. This is what `NAME_MAX` is measured
    /// against.
    public var value: String {
        "\(stem).\(Self.fileExtension)"
    }

    /// Scalars that make the write fail rather than merely look odd.
    ///
    /// Deliberately short. Everything else that was probed — `:`, DEL, newline,
    /// non-ASCII — writes fine on Darwin, and refusing it would be inventing a rule the
    /// filesystem does not have and coupling this type to the label's ASCII limit.
    ///
    /// **`Unicode.Scalar`, not `Character`, and that is a bug fix rather than a preference.**
    /// A cross-vendor review found `"a/\u{0301}b"` passing validation: `/` followed by a
    /// combining acute is a *single* `Character` that is not equal to `Character("/")`, so a
    /// grapheme-level check waves the path separator straight through and the write then
    /// fails on a directory nobody created. It is the second location of the same
    /// grapheme-versus-scalar mistake the in-loop review found in `DesignName` — fixed
    /// there, missed here.
    private static let prohibited: Set<Unicode.Scalar> = ["/", "\0"]

    private init(stem: String) {
        self.stem = stem
    }

    /// Validates `rawStem` — the name **without** the extension — trimming leading and
    /// trailing whitespace first.
    ///
    /// The input is the stem rather than a whole file name so that "rejects empty" means
    /// something: an empty stem is Catroid's bug, a file literally named `.dst`.
    ///
    /// Order is `empty`, then prohibited characters, then length. The length check runs
    /// last and measures `value`, so the extension's four bytes are inside the budget.
    public static func validating(
        _ rawStem: String
    ) -> Result<DSTFileName, DSTFileNameProblem> {
        let trimmed = rawStem.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return .failure(.empty)
        }
        if let offender = trimmed.unicodeScalars.first(where: { prohibited.contains($0) }) {
            return .failure(.prohibitedCharacter(Character(offender)))
        }

        // Constructed before measuring, because the bound is on the whole file name and
        // the extension is this type's to add.
        let candidate = DSTFileName(stem: trimmed)
        let byteCount = candidate.value.utf8.count
        guard byteCount <= maximumByteLength else {
            return .failure(
                .tooLongForFilesystem(byteCount: byteCount, limit: maximumByteLength)
            )
        }
        return .success(candidate)
    }

    /// Derives a file name from a validated design name, replacing what the filesystem
    /// cannot carry rather than refusing it.
    ///
    /// **This exists because the two fields really are independent**, which only becomes
    /// concrete when you try to use one as the other: `DesignName` accepts `/` — the `LA`
    /// field carries it untouched, measured — and `validating(_:)` rejects it, so deriving
    /// through the strict path would fail for a name the user was just told was fine.
    /// Sanitising is Catroid's `sanitizeFileName`, which is the one thing that method gets
    /// right; the empty check it lacks is unnecessary here, for the reason below.
    ///
    /// **Total, and the parameter type is what makes it total.** It takes a `DesignName`
    /// rather than a `String` so the result needs no `Result`: a validated design name is
    /// non-empty, **printable ASCII** and at most 15 characters, so substituting one ASCII
    /// scalar for another leaves a stem that is still non-empty and still at most 15 bytes —
    /// both bounds well inside `maximumByteLength`. The "printable" half is load-bearing:
    /// under the earlier `Character.isASCII` rule a 15-character name could be 28
    /// bytes. A `String` overload could be handed 300
    /// bytes of emoji and would have to be failable, so there deliberately is not one.
    public static func sanitising(_ designName: DesignName) -> DSTFileName {
        // Scalar-wise like `validating(_:)`, though here it changes nothing: a `DesignName`
        // is printable ASCII, so every `Character` is already exactly one scalar. Written
        // the same way so the two cannot drift, which is how the grapheme bug survived in
        // one of them and not the other.
        DSTFileName(stem: String(String.UnicodeScalarView(
            designName.value.unicodeScalars.map { prohibited.contains($0) ? "_" : $0 }
        )))
    }
}

/// Why a file name was refused (US-308).
///
/// `Error` so callers may use `Result.get()`. As with `DesignNameProblem`, the wording
/// lives in the app's String Catalog (ADR-011), not here.
public enum DSTFileNameProblem: Error, Hashable, Sendable {
    /// Empty, or nothing but whitespace. Catroid's missing check.
    case empty

    /// A character the filesystem cannot carry: `/`, which silently becomes a path
    /// separator, or NUL, which truncates the path at an unpredictable point.
    case prohibitedCharacter(Character)

    /// `byteCount` is the UTF-8 length of the **whole** file name, extension included, so
    /// a caller can render the overshoot without re-deriving where the four bytes went.
    case tooLongForFilesystem(byteCount: Int, limit: Int)
}
