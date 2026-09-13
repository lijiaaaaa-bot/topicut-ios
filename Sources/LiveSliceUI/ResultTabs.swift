// Why: the workbench shows two lists from one slicing call — complete topics and short highlights
// (ADR-0022). Tabs keep intrinsic 话题/金句 width; the token/¥ line yields or wraps under them
// (ADR-0030/0031). Clip titles stay in the list, not as chips. Old projects without highlights
// still get one honest panel and one paid button.

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
        // Tabs must keep their intrinsic width. A prior fee row used
        // layoutPriority(1) + minWidth 128 + maxWidth ∞ and crushed 话题/金句
        // to empty capsules while the token line stayed visible.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                segmented
                usageLabel(lineLimit: 1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .layoutPriority(0)
                overflow
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    segmented
                    Spacer(minLength: 8)
                    overflow
                }
                usageLabel(lineLimit: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 2)
        .padding(.top, -2)
    }

    private var segmented: some View {
        HStack(spacing: 8) {
            segment(.topics)
            segment(.highlights)
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
    }

    private func segment(_ t: ResultTab) -> some View {
        let on = tab == t
        return Button {
            withAnimation(StudioTheme.motion) { tab = t }
        } label: {
            Text(t.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? .white : StudioTheme.muted)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if on {
                        Capsule().fill(StudioTheme.accent)
                    } else {
                        Capsule().fill(StudioTheme.raised)
                    }
                }
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
        .accessibilityLabel(t.title)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityValue(pillValue(t.clips(in: document)?.count))
    }

    @ViewBuilder
    private func usageLabel(lineLimit: Int) -> some View {
        if let usage = document.llm {
            let line = LLMCost.usageLine(
                usage: usage, slicedWith: slicedWith, generatedAt: document.generatedAt
            )
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StudioTheme.cyan)
                Text(line)
                    .font(.caption.monospaced())
                    .foregroundStyle(StudioTheme.muted)
                    .lineLimit(lineLimit)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
            }
            .accessibilityLabel(line)
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
