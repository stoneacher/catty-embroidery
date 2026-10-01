import EditorCore
import EmbroideryEngine
import Foundation

/// One group of the brick palette (US-409).
///
/// The kinds and their order are the package's (`PaletteGroup.kinds`), so the completeness
/// test over `BrickKind.allCases` covers what the palette shows. This value adds only what the
/// package cannot hold: catalog text, since SwiftPM does not compile `.xcstrings` (ADR-039).
nonisolated struct PaletteSection: Equatable, Identifiable {
    let id: PaletteGroup
    let title: String
    let rows: [PaletteRowPresentation]

    /// The palette, in the order it shows.
    static func sections(locale: Locale = .current) -> [PaletteSection] {
        PaletteGroup.allCases.map { group in
            PaletteSection(
                id: group,
                title: resolve(title(of: group), locale: locale),
                rows: group.kinds.map { PaletteRowPresentation(kind: $0, locale: locale) }
            )
        }
    }

    private static func title(of group: PaletteGroup) -> LocalizedStringResource {
        switch group {
        case .embroidery: .paletteGroupEmbroidery
        case .motion: .paletteGroupMotion
        case .controlAndData: .paletteGroupControl
        }
    }
}

/// One brick the palette offers (US-409): the brick as it will appear, and what it does.
///
/// **A value, not a view**, for `BrickRowPresentation`'s reason: the VoiceOver label is the
/// criterion, and only a value lets a test read it.
nonisolated struct PaletteRowPresentation: Equatable, Identifiable {
    let id: BrickKind
    /// The brick as it will appear in the script: the sentence of the kind's template. For a
    /// loop it is the opener alone, since that is the row the tap lands on.
    let text: String
    /// What the brick does, in one line.
    let description: String
    /// The text, then the description. The description goes in the label, not in a hint:
    /// hints can be turned off, and the element itself must say what the brick does.
    let accessibilityLabel: String
    /// The template's thread colour, for the one kind that has one.
    let threadColor: ThreadColor?

    init(kind: BrickKind, locale: Locale) {
        // Every template has a head; a loop's is its opener.
        let head = kind.template()[0]
        let text = BrickRowPresentation.text(of: head, locale: locale)
        let description = resolve(Self.description(of: kind), locale: locale)
        id = kind
        self.text = text
        self.description = description
        accessibilityLabel = resolve(.paletteRowAccessibilityLabel(text, description), locale: locale)
        threadColor = BrickRowPresentation.threadColor(of: head)
    }

    /// Exhaustive with no `default:`, so a new kind is a compile error here rather than a row
    /// with no description. `.loopEnd` is never offered (ADR-035), but this mapping has to be
    /// total, so it is given its opener's meaning.
    private static func description(of kind: BrickKind) -> LocalizedStringResource {
        switch kind {
        case .stitch: .paletteDescriptionStitch
        case .setThreadColor: .paletteDescriptionThreadColor
        case .runningStitch: .paletteDescriptionRunningStitch
        case .zigZagStitch: .paletteDescriptionZigzagStitch
        case .tripleStitch: .paletteDescriptionTripleStitch
        case .sewUp: .paletteDescriptionSewUp
        case .stopRunningStitch: .paletteDescriptionStopStitch
        case .writeEmbroideryToFile: .paletteDescriptionWriteFile
        case .placeAt: .paletteDescriptionPlaceAt
        case .setX: .paletteDescriptionSetX
        case .setY: .paletteDescriptionSetY
        case .changeXBy: .paletteDescriptionChangeX
        case .changeYBy: .paletteDescriptionChangeY
        case .moveNSteps: .paletteDescriptionMove
        case .turnLeft: .paletteDescriptionTurnLeft
        case .turnRight: .paletteDescriptionTurnRight
        case .pointInDirection: .paletteDescriptionPointDirection
        case .wait: .paletteDescriptionWait
        case .forever: .paletteDescriptionForever
        case .repeatLoop, .loopEnd: .paletteDescriptionRepeat
        case .setVariable: .paletteDescriptionSetVariable
        case .changeVariableBy: .paletteDescriptionChangeVariable
        }
    }
}

/// The palette's presentation and the scroll request its last insert left (US-409).
///
/// A value so that the invariant "every insert is a new request" lives in one mutating method.
/// Nothing else can write `insertion`.
nonisolated struct PaletteState: Equatable {
    var isPresented = false
    private(set) var insertion: PaletteInsertion?

    /// An insert landed at `index`: close the palette and ask the list to show it.
    mutating func inserted(at index: Int) {
        isPresented = false
        insertion = PaletteInsertion(index: index, serial: (insertion?.serial ?? -1) + 1)
    }
}

/// What the script list scrolls to after a palette tap (US-409). The serial makes two inserts
/// at the same index two distinct values, so the list's `onChange` fires for both.
nonisolated struct PaletteInsertion: Equatable {
    let index: Int
    let serial: Int
}

private nonisolated func resolve(_ resource: LocalizedStringResource, locale: Locale) -> String {
    var resource = resource
    resource.locale = locale
    return String(localized: resource)
}
