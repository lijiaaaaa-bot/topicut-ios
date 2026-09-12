// Why: the workbench shows two lists from one slicing call — complete topics and short highlights
// (ADR-0022). The bar is 话题|金句, token/cost, and an overflow 重新切片 (ADR-0030). Clip titles
// stay in the list below, not as a second chip row. Old projects without highlights still get
// one honest panel and one paid button.

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

/// Segmented 话题|金句, usage, overflow 重新切片. No title chips (they duplicated the list).
struct ResultTabBar: View {
    let document: EDLDocument
    let slicedWith: String?
    @Binding var tab: ResultTab
    let onReslice: () -> Void
    var sliceTasteStale: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            segmented
            Spacer(minLength: 8)
            usage
            overflow
        }
        .padding(.horizontal, 4)
        .padding(.top, -4)
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            segment(.topics)
            Text("|")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(StudioTheme.muted.opacity(0.45))
            segment(.highlights)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(StudioTheme.raised, in: Capsule())
    }

    private func segment(_ t: ResultTab) -> some View {
        let on = tab == t
        return Button {
            withAnimation(StudioTheme.motion) { tab = t }
        } label: {
            HStack(spacing: 4) {
                if on {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .bold))
                }
                Text(t.title)
                    .font(.subheadline.weight(on ? .semibold : .medium))
            }
            .foregroundStyle(on ? .white : StudioTheme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.title)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityValue(pillValue(t.clips(in: document)?.count))
    }

    @ViewBuilder
    private var usage: some View {
        if let usage = document.llm {
            HStack(spacing: 4) {
                Text(LLMCost.tokenText(usage))
                if let charge = LLMCost.estimate(usage: usage, slicedWith: slicedWith, generatedAt: document.generatedAt) {
                    Text("·")
                    Text(LLMCost.text(charge))
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(StudioTheme.muted)
            .lineLimit(1)
        }
    }

    private var overflow: some View {
        Menu {
            Button("重新切片", action: onReslice)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(StudioTheme.muted)
                .frame(width: 32, height: 32)
                .overlay(alignment: .topTrailing) {
                    if sliceTasteStale {
                        Circle().fill(StudioTheme.accent).frame(width: 7, height: 7)
                    }
                }
        }
        .accessibilityLabel(sliceTasteStale ? "按新偏好重新切片" : "更多")
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
