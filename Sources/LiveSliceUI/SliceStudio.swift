// Why: ADR-0028/0029 — after ASR the pipeline stops here. Phone-first: one big status, card
// presets, chip fine-tune, sticky 开始切片. Not a desktop Form of segmented controls.

import LiveSliceCore
import SwiftUI

struct SliceStudio: View {
    @Binding var taste: SlicingTaste
    let info: AwaitingSliceInfo
    let sliceError: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            GlowBackdrop(intensity: 0.85)
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        hero
                        presetCards
                        fineTune
                        if let error = sliceError {
                            errorBlock(error)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                Text("会计费 · 只发文字")
                    .font(.caption2)
                    .foregroundStyle(StudioTheme.muted)
                Button(action: onConfirm) {
                    Text("开始切片")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityLabel("开始切片")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(.ultraThinMaterial.opacity(0.35))
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Button("关闭", action: onCancel)
                .font(.body.weight(.medium))
                .foregroundStyle(StudioTheme.muted)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(info.cueCount)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(summaryLine)
                .font(.subheadline)
                .foregroundStyle(StudioTheme.muted)
        }
        .padding(.top, 8)
    }

    private var summaryLine: String {
        let locale = Locale.current.localizedString(forIdentifier: info.localeIdentifier) ?? info.localeIdentifier
        let words = info.hasWords ? "含词级时间" : "无词级时间"
        return "\(locale) · \(words)"
    }

    private var presetCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(SliceTastePreset.allCases) { preset in
                StudioChoiceCard(
                    title: preset.title,
                    note: preset.note,
                    selected: SliceTastePreset.matching(taste) == preset
                ) {
                    taste = preset.taste
                }
            }
        }
    }

    private var fineTune: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(taste.topicDensity.note)
                .font(.caption)
                .foregroundStyle(StudioTheme.muted)
                .padding(.horizontal, 20)
            StudioChipRow(values: TopicDensity.allCases, selection: $taste.topicDensity) { $0.title }
            Text(taste.highlightSpan.note)
                .font(.caption)
                .foregroundStyle(StudioTheme.muted)
                .padding(.horizontal, 20)
            StudioChipRow(values: HighlightSpan.allCases, selection: $taste.highlightSpan) { $0.title }
        }
        .padding(.horizontal, -20)
    }

    private func errorBlock(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(error)
                .font(.footnote.monospaced())
                .foregroundStyle(.orange)
                .textSelection(.enabled)
            ErrorShareButton(message: error)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudioTheme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
