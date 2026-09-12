// Why: ADR-0028/0030 — after ASR the pipeline stops here. Three density cards, 亮点 chips,
// sticky 开始切片. Not a desktop Form; not five combined tags on the primary path.

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
                    VStack(alignment: .leading, spacing: 28) {
                        hero
                        densityCards
                        highlightBand
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
            confirmBar
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
        VStack(spacing: 8) {
            Text("转写完成 · 可开始切片")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Text(summaryLine)
                .font(.subheadline)
                .foregroundStyle(StudioTheme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 12)
    }

    private var summaryLine: String {
        let locale = Locale.current.localizedString(forIdentifier: info.localeIdentifier) ?? info.localeIdentifier
        let words = info.hasWords ? "含词级时间" : "无词级时间"
        return "\(info.cueCount) 条字幕 · \(locale) · \(words)"
    }

    private var densityCards: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(TopicDensity.allCases, id: \.self) { density in
                StudioChoiceTile(
                    title: density.title,
                    note: density.note,
                    tag: density.studioTag,
                    selected: taste.topicDensity == density
                ) {
                    apply(density)
                }
            }
        }
    }

    /// Card tap writes a known `SliceTastePreset` pair, then 亮点 chips can override span.
    private func apply(_ density: TopicDensity) {
        switch density {
        case .fewer: taste = SliceTastePreset.concise.taste
        case .standard: taste = SliceTastePreset.balanced.taste
        case .more: taste = SliceTastePreset.dense.taste
        }
    }

    private var highlightBand: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("亮点长度", systemImage: "sparkle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(taste.highlightSpan.studioChip)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(StudioTheme.muted)
            }
            StudioChipRow(values: HighlightSpan.allCases, selection: $taste.highlightSpan) { $0.studioChip }
                .padding(.horizontal, -20)
        }
    }

    private var confirmBar: some View {
        VStack(spacing: 10) {
            Button(action: onConfirm) {
                Text("开始切片")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityLabel("开始切片")
            Label("会计费 · 只发文字", systemImage: "info.circle")
                .font(.caption2)
                .foregroundStyle(StudioTheme.muted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial.opacity(0.35))
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
