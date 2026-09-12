// Why: the workbench shows two lists from one slicing call — complete topics and short highlights
// (ADR-0022). The switch is two pills on the line that already carries the token/cost readout, so
// the screen gains no new row. A project sliced before highlights existed gets one honest panel:
// what is missing, what re-slicing costs, one button; nothing re-slices by itself.

import LiveSliceCore
import SwiftUI

enum ResultTab: Hashable {
    case topics
    case highlights

    var title: String {
        switch self {
        case .topics: "话题"
        case .highlights: "金句"
        }
    }

    /// The list this tab shows; `nil` when the document predates highlights.
    func clips(in document: EDLDocument) -> [EDLClip]? {
        switch self {
        case .topics: document.clips
        case .highlights: document.highlights
        }
    }
}

/// Two pills on the left, the LLM usage readout on the right.
struct ResultTabBar: View {
    let document: EDLDocument
    let slicedWith: String?
    @Binding var tab: ResultTab

    var body: some View {
        HStack(spacing: 8) {
            pill(.topics)
            pill(.highlights)
            Spacer()
            if let usage = document.llm {
                HStack(spacing: 6) {
                    Text(LLMCost.tokenText(usage))
                    if let charge = LLMCost.estimate(usage: usage, slicedWith: slicedWith, generatedAt: document.generatedAt) {
                        Text("·")
                        Text(LLMCost.text(charge))
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(StudioTheme.muted)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, -4)
    }

    private func pill(_ t: ResultTab) -> some View {
        let on = tab == t
        let count = t.clips(in: document)?.count
        return Button {
            withAnimation(StudioTheme.motion) { tab = t }
        } label: {
            HStack(spacing: 5) {
                Text(t.title)
                    .font(.subheadline.weight(on ? .semibold : .medium))
                if let count {
                    Text("\(count)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(on ? StudioTheme.accent : StudioTheme.muted)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(StudioTheme.muted)
                }
            }
            .foregroundStyle(on ? .white : StudioTheme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(on ? StudioTheme.raised : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Color.white.opacity(0.08) : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.title)
        .accessibilityValue(pillValue(count))
    }
}

private func pillValue(_ count: Int?) -> String {
    guard let count else { return "需重新切片" }
    return "\(count)"
}

/// Shown in place of the list when the project was sliced before highlights existed.
struct StaleHighlightsPanel: View {
    let document: EDLDocument
    let slicedWith: String?
    let reslice: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            Image(systemName: "quote.opening")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(StudioTheme.muted)
            Text("这个项目是旧版本切的，还没有金句")
                .font(.subheadline)
                .foregroundStyle(.white)
            Text(costLine)
                .font(.caption)
                .foregroundStyle(StudioTheme.muted)
                .multilineTextAlignment(.center)
            Button(action: reslice) {
                Label("重新切片", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(StudioTheme.raised, in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    /// What the last call cost is the best available estimate for the next one on the same transcript.
    private var costLine: String {
        guard let usage = document.llm else { return "重新切片会再调用一次 AI 服务" }
        if let charge = LLMCost.estimate(usage: usage, slicedWith: slicedWith, generatedAt: document.generatedAt) {
            return "重新切片会再调用一次 AI 服务，上次 \(LLMCost.text(charge))"
        }
        return "重新切片会再调用一次 AI 服务，上次 \(LLMCost.tokenText(usage))"
    }
}
