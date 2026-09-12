// Why: phone-sized choice surfaces shared by 切片 / 成片 studios — large tappable cards and
// chip rows, not desktop Form + segmented panels (ADR-0029).

import SwiftUI

struct StudioChoiceCard: View {
    let title: String
    let note: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(StudioTheme.muted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? StudioTheme.accent : StudioTheme.muted.opacity(0.5))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? StudioTheme.accent.opacity(0.16) : StudioTheme.raised,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(selected ? StudioTheme.accent.opacity(0.7) : Color.white.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Compact 3-up card for 切片工作室 density (title + note + tag).
struct StudioChoiceTile: View {
    let title: String
    let note: String
    let tag: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(StudioTheme.accent)
                    }
                }
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(StudioTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tag)
                    .font(.caption2)
                    .foregroundStyle(StudioTheme.muted.opacity(0.85))
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(
                selected ? StudioTheme.accent.opacity(0.14) : StudioTheme.raised,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? StudioTheme.accent.opacity(0.85) : Color.white.opacity(0.06), lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct StudioChipRow<Value: Hashable>: View {
    let values: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    let on = selection == value
                    Button {
                        selection = value
                    } label: {
                        Text(title(value))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(on ? .black : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(on ? StudioTheme.accent : StudioTheme.raised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(title(value))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
    }
}
