import EditorCore
import EmbroideryEngine
import SwiftUI

/// The curated thread palette (US-410, ADR-040): a grid of fixed swatches.
///
/// **The swatches are design data and never adapt** — `Color(ThreadColor)` is verbatim sRGB, the
/// same colour in dark mode as in light, because it is the colour the stage draws. Only the
/// ring and the selection badge are chrome. Selection is a checkmark and a thicker ring plus
/// the `.isSelected` trait, never colour alone, and every swatch speaks its name.
///
/// A stored colour that is not a swatch is shown first as "Current Colour", selected, and left
/// untouched until a swatch is tapped — so opening a brick never rewrites its colour.
struct ThreadPaletteGrid: View {
    let selectedHex: String
    let select: (ThreadSwatch) -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
            if ThreadSwatch(hex: selectedHex) == nil {
                swatch(
                    color: ThreadColor(hexString: selectedHex),
                    name: String(localized: .parameterThreadCurrent),
                    isSelected: true
                )
                .accessibilityAddTraits(.isSelected)
            }
            ForEach(ThreadSwatch.allCases, id: \.self) { swatch in
                Button {
                    select(swatch)
                } label: {
                    self.swatch(
                        color: ThreadColor(hexString: swatch.hex),
                        name: ParameterEditorText.name(of: swatch, locale: locale),
                        isSelected: swatch.hex == selectedHex
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(swatch.hex == selectedHex ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    /// The ring is chrome and adapts — `.secondary`, not `.separator`, which left black, navy and
    /// brown nearly edgeless on a dark sheet (`swift-code-reviewer`, US-410).
    private func swatch(color: ThreadColor?, name: String, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                // A hex ADR-015's parser refuses has no colour; the stage keeps the previous
                // thread for it, so the swatch shows an empty ring rather than a guess.
                .fill(color.map { Color($0) } ?? .clear)
                .overlay(Circle().strokeBorder(isSelected ? .primary : .secondary, lineWidth: isSelected ? 3 : 1))
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .padding(4)
                    .background(.background, in: Circle())
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name))
    }
}
