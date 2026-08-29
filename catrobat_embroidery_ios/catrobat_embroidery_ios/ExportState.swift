import EmbroideryEngine
import Foundation
import StagePreview

/// Where the export has got to (ADR-026).
///
/// **Three cases, not the four the story specifies.** `preparing` was dropped on
/// measurement: in release configuration, building a `DSTFile` from a 52 240-stitch stream
/// takes 2.6–3.0 ms and writing it 0.47 ms, so at the milestone's own exit-criterion size
/// the whole export is under 4 ms — a state no user can perceive, reachable in a test only
/// by injecting a gated writer double, and renderable by nothing. That is the same call the
/// ROADMAP already made when it struck `failed` from the *run* enum for having no producer,
/// and the same call ADR-028 made when it deleted an unreachable accessibility hint rather
/// than sending it to ~75 Crowdin translators.
///
/// `failed`, by contrast, genuinely has producers — disk, and after US-211 a header field
/// that cannot describe the design — which is why the ROADMAP's correction moved it here
/// from the run enum in the first place.
enum ExportState: Equatable {
    /// Nothing prepared: no run has ended, the design was discarded, or the name is not yet
    /// usable.
    case idle

    /// A file is on disk at `URL`, ready for a `ShareLink` to hand over.
    case ready(URL)

    case failed(ExportError)
}

/// Why an export could not be prepared.
///
/// Distinct from `DSTSerializationError`, which it wraps: that type is the engine's data for
/// a caller to render, and ADR-011 keeps user-facing wording in the app's String Catalog.
/// This is where the wording is attached.
/// `Equatable` rather than `Hashable`: `DSTSerializationError` is `Equatable` only, and
/// nothing here is ever a dictionary key — `ExportState` needs equality and no more.
enum ExportError: Error, Equatable {
    /// The design cannot be described by a DST header (US-211, ADR-025).
    case serialization(DSTSerializationError)

    /// The temporary file could not be written — a full disk, most plausibly.
    case writeFailed
}

extension ExportError {
    /// The sentence shown under the stage and spoken as the disabled share control's hint.
    ///
    /// One catalog entry serving both, deliberately: the visible notice and the hint cannot
    /// disagree if they are the same string, which is the argument `StageTransportRow`
    /// already makes for the transport title being its own accessibility label.
    var message: LocalizedStringResource {
        switch self {
        case let .serialization(.fieldOverflow(field, _, limit)):
            Self.overflowMessage(field: field, limit: limit)
        case .writeFailed:
            .stageExportErrorWriteFailed
        }
    }

    /// Maps the overflowing field to a sentence a user can act on.
    ///
    /// **Six of the twelve fields route to one generic message, and that is the decision
    /// here.** ADR-025 records that `Field.limit` is meaningless for `LA`, `AX`, `AY`, `MX`,
    /// `MY` and `PD` — none of them can overflow — so there is no honest sentence to write
    /// for them. Inventing six is the mistake ADR-028 had to undo (copy shipped to ~75
    /// translators for a state no one reaches); trapping on them is the mistake ADR-025
    /// removed. A generic arm is the third option, and the switch stays exhaustive so that a
    /// thirteenth field would be a compile error rather than a silent fallback.
    ///
    /// The four extent fields share one message: `+X`, `-X`, `+Y` and `-Y` all mean "the
    /// design reaches too far", and naming the axis would be precision the user cannot act
    /// on differently.
    private static func overflowMessage(
        field: DSTHeader.Field, limit: Int
    ) -> LocalizedStringResource {
        switch field {
        case .stitchCount:
            .stageExportErrorStitchLimit(limit)
        case .colorBlocks:
            .stageExportErrorColorLimit(limit)
        case .extentPlusX, .extentMinusX, .extentPlusY, .extentMinusY:
            .stageExportErrorSizeLimit(formattedLength(units: limit))
        case .label, .endOffsetX, .endOffsetY, .multiVolumeX, .multiVolumeY, .previousDesign:
            .stageExportErrorUnknown
        }
    }

    /// An extent limit in embroidery units, rendered as a length the user can compare against
    /// the hoop.
    ///
    /// `usage: .asProvided` for the reason `StageView.hoopSizeDescription` records: the
    /// default lets the formatter pick the locale's preferred unit and turns 999.9 mm into
    /// "99.99 cm", which is arithmetically right and wrong for the domain — ADR-007 defines
    /// the stage in millimetres, DST is a millimetre-based format, and machine vendors
    /// specify hoops in millimetres. The number and the unit abbreviation are still localized;
    /// only the *choice* of unit is pinned.
    ///
    /// The conversion comes from `StageGeometry.millimetresPerEmbroideryUnit`, which is
    /// derived from ADR-007's unit chain rather than re-typed as `0.1`.
    private static func formattedLength(units: Int) -> String {
        Measurement(
            value: Double(units) * StageGeometry.millimetresPerEmbroideryUnit,
            unit: UnitLength.millimeters
        )
        .formatted(.measurement(width: .abbreviated, usage: .asProvided))
    }
}
