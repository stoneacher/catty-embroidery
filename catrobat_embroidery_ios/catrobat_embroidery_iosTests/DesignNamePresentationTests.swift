@testable import catrobat_embroidery_ios
import EmbroideryEngine
import Foundation
import SwiftUI
import Testing

/// US-308's story-specific definition of done: **the counter moves below the field at AX1
/// rather than truncating**, and the field says what is wrong with a name.
///
/// The layout itself is only checkable by screenshot, so the *policy* lives in a pure
/// function and is checked here — the mitigation ADR-028 used for Reduce Motion, where the
/// decision about what a setting means was hoisted out of `body` so two views could not
/// disagree about it.
@Suite("Design name presentation")
struct DesignNamePresentationTests {
    // MARK: - The AX1 rule

    /// The threshold, from both sides. Asserting only the AX1 case would pass against a
    /// function that always stacks.
    @Test("the counter sits beside the field below AX1 and beneath it from AX1 up")
    func theCounterMovesAtAX1() {
        #expect(DesignNameFieldLayout.axis(for: .large) == .horizontal)
        #expect(DesignNameFieldLayout.axis(for: .xxxLarge) == .horizontal)
        #expect(DesignNameFieldLayout.axis(for: .accessibility1) == .vertical)
        #expect(DesignNameFieldLayout.axis(for: .accessibility5) == .vertical)
    }

    /// **Every accessibility size stacks, and every standard size does not.** Enumerated
    /// rather than sampled, so a threshold moved by one step cannot slip through between two
    /// chosen examples.
    @Test("the rule is exactly the accessibility-sizes boundary")
    func theRuleIsTheAccessibilityBoundary() {
        for size in DynamicTypeSize.allCases {
            let expected: Axis = size.isAccessibilitySize ? .vertical : .horizontal
            #expect(DesignNameFieldLayout.axis(for: size) == expected, "\(size)")
        }
    }

    // MARK: - The counter

    /// The counter and the validator must count the same string, or the field can read
    /// "15/15" while reporting `.tooLong`. Both go through `DesignName.normalised`.
    @Test("the counter counts what validation counts")
    func theCounterAgreesWithValidation() {
        #expect(DesignNameFieldLayout.characterCount(of: "Rose") == 4)
        #expect(DesignNameFieldLayout.characterCount(of: "  Rose  ") == 4, "trailing space is free")
        #expect(DesignNameFieldLayout.characterCount(of: "") == 0)
    }

    // MARK: - The messages

    @Test("each name problem has its own message")
    func eachProblemReadsDifferently() {
        let empty = String(localized: DesignNameProblem.empty.message)
        let tooLong = String(localized: DesignNameProblem.tooLong(count: 20, limit: 15).message)
        let character = String(localized: DesignNameProblem.nonASCII(character: "ö").message)

        #expect(Set([empty, tooLong, character]).count == 3)
        for message in [empty, tooLong, character] {
            #expect(message.contains("stage.name") == false, "fell back to a key")
            #expect(message.isEmpty == false)
        }
    }

    /// The limit is named, the typed count is not — the counter beside the field already
    /// shows that, and repeating it is noise.
    @Test("the too-long message names the limit rather than the count")
    func theTooLongMessageNamesTheLimit() {
        let message = String(localized: DesignNameProblem.tooLong(count: 20, limit: 15).message)
        #expect(message.contains("15"))
        #expect(message.contains("20") == false)
    }

    @Test("the character message quotes the offending character")
    func theCharacterMessageQuotesTheCharacter() {
        #expect(String(localized: DesignNameProblem.nonASCII(character: "ö").message).contains("ö"))
    }

    /// **An invisible offender is named by code point instead.** A non-breaking space or a
    /// zero-width space rejected as "“ ” cannot be stored" tells the user nothing — the
    /// message would appear to quote an empty string, and the character is invisible in the
    /// field too. This is the case a smart keyboard or a paste from a web page actually
    /// produces.
    @Test("an invisible character is named by its code point")
    func anInvisibleCharacterIsNamedByCodePoint() {
        let nonBreakingSpace = String(
            localized: DesignNameProblem.nonASCII(character: "\u{00A0}").message
        )
        #expect(nonBreakingSpace.contains("U+00A0"))

        let zeroWidth = String(
            localized: DesignNameProblem.nonASCII(character: "\u{200B}").message
        )
        #expect(zeroWidth.contains("U+200B"))
    }

    /// The control: an ordinary visible character is *not* rendered as a code point, or the
    /// test above would pass against a mapping that code-pointed everything.
    @Test("a visible character is shown as itself, not as a code point")
    func aVisibleCharacterIsShownAsItself() {
        let message = String(localized: DesignNameProblem.nonASCII(character: "ö").message)
        #expect(message.contains("U+") == false)
    }
}
