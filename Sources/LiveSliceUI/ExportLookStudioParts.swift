// Why: tune + NL describe panes for ExportLookStudio, parked under 高级 so the primary path
// stays presets and framing chips (ADR-0030).

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

struct LookTunePane: View {
    @Binding var style: CaptionStyle
    @Binding var tune: CaptionTune
    let framing: FramingMode
    let hasWords: Bool
    let retranscribe: () -> Void
    var bandY: Binding<Double>
    var fontScale: Binding<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(ExportLookText.framingNote(framing))
                .font(.caption)
                .foregroundStyle(StudioTheme.muted)
            Text(ExportLookText.styleNote(style, hasWords: hasWords))
                .font(.caption)
                .foregroundStyle(StudioTheme.muted)
            StudioChipRow(values: CaptionStyle.allCases, selection: $style) {
                ExportLookText.styleTitle($0)
            }
            .padding(.horizontal, -20)
            if style == .highlightWord, !hasWords {
                Button("重新转写", action: retranscribe)
                    .buttonStyle(QuietButtonStyle())
            }
            VStack(alignment: .leading, spacing: 10) {
                Slider(value: bandY, in: 0...1)
                Text("字幕带 \(Int(tune.bandY * 100))%")
                    .font(.caption)
                    .foregroundStyle(StudioTheme.muted)
                Slider(value: fontScale, in: 0.6...1.8)
                Text(String(format: "字号 ×%.1f", tune.fontScale))
                    .font(.caption)
                    .foregroundStyle(StudioTheme.muted)
                HStack(spacing: 10) {
                    ForEach(LookColorChip.textChoices, id: \.self) { hex in
                        LookColorChip.swatch(hex, selected: tune.textHex == hex) {
                            tune = CaptionTune(
                                bandY: tune.bandY, fontScale: tune.fontScale,
                                textHex: hex, accentHex: tune.accentHex
                            )
                        }
                    }
                }
                HStack(spacing: 10) {
                    ForEach(LookColorChip.accentChoices, id: \.self) { hex in
                        LookColorChip.swatch(hex, selected: tune.accentHex == hex) {
                            tune = CaptionTune(
                                bandY: tune.bandY, fontScale: tune.fontScale,
                                textHex: tune.textHex, accentHex: hex
                            )
                        }
                    }
                }
            }
            .disabled(!style.burnsCaptions)
            .opacity(style.burnsCaptions ? 1 : 0.35)
        }
    }
}

struct LookDescribePane: View {
    @Binding var prompt: String
    let describeError: String?
    let describing: Bool
    let canSubmit: Bool
    let submit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("竖屏跟人，大白字靠下", text: $prompt, axis: .vertical)
                .lineLimit(3...5)
                .padding(12)
                .background(StudioTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if let describeError {
                Text(describeError).font(.footnote).foregroundStyle(.orange)
            }
            Button(action: submit) {
                if describing { ProgressView() } else { Text("套用").frame(maxWidth: .infinity) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSubmit)
        }
    }
}
