// Why: colour chips for ExportLookStudio tune pane. Preset tag wrap removed — studios use
// StudioChoiceCard instead (ADR-0029).

import LiveSliceRender
import SwiftUI

enum LookColorChip {
    static let textChoices = ["FFFFFF", "FFE08A", "FF6B6B", "7CFFB2"]
    static let accentChoices = ["FFD60A", "5AC8FA", "FF375F", "BF5AF2"]

    static func swatch(_ hex: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color(for: hex))
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(.white.opacity(selected ? 1 : 0.25), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hex)
    }

    /// Chip palette is a closed set of RRGGBB literals compiled into the binary.
    private static func color(for hex: String) -> Color {
        switch hex {
        case "FFFFFF": Color.white
        case "FFE08A": Color(red: 1, green: 0.88, blue: 0.54)
        case "FF6B6B": Color(red: 1, green: 0.42, blue: 0.42)
        case "7CFFB2": Color(red: 0.49, green: 1, blue: 0.70)
        case "FFD60A": Color(red: 1, green: 0.84, blue: 0.04)
        case "5AC8FA": Color(red: 0.35, green: 0.78, blue: 0.98)
        case "FF375F": Color(red: 1, green: 0.22, blue: 0.37)
        case "BF5AF2": Color(red: 0.75, green: 0.35, blue: 0.95)
        default: Color.white
        }
    }
}
