// Why: workbench clip list — numbered rows with poster, full title, duration, export mark.
// Titles stay here, never as ResultTabBar chips (ADR-0030 / 0031). Phone and iPad share this.

import LiveSliceCore
import SwiftUI

/// Number, first frame, title, duration, export mark. Tap plays; ⋮ opens 依据 on phone rows.
struct ClipTable: View {
    let sourceURL: URL
    let clips: [EDLClip]
    let selectedID: String
    let renders: [String: ClipRenderState]
    let select: (String) -> Void
    /// Tap on the selected row; nil where the rationale is already on screen (iPad).
    let showRationale: (() -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                        row(index: index + 1, clip: clip)
                            .id(clip.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: selectedID) { _, id in
                withAnimation(StudioTheme.motion) { proxy.scrollTo(id, anchor: nil) }
            }
        }
    }

    private func row(index: Int, clip: EDLClip) -> some View {
        let isSelected = clip.id == selectedID
        return HStack(spacing: 4) {
            Button {
                if clip.id == selectedID {
                    showRationale?()
                } else {
                    withAnimation(StudioTheme.motion) { select(clip.id) }
                }
            } label: {
                rowLabel(index: index, clip: clip)
            }
            .buttonStyle(.plain)
            if let showRationale {
                Menu {
                    Button("依据") {
                        select(clip.id)
                        showRationale()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.medium))
                        .foregroundStyle(StudioTheme.muted)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("依据")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(isSelected ? StudioTheme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func rowLabel(index: Int, clip: EDLClip) -> some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", index))
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(StudioTheme.muted)
                .frame(width: 28, alignment: .leading)
            ClipPoster(url: sourceURL, seconds: clip.startSec, maximumSize: CGSize(width: 180, height: 120))
                .frame(width: 52, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(clip.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(TimeText.clock(clip.keptDurationSec))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(StudioTheme.muted)
                    exportMark(for: clip)
                }
            }
            Spacer(minLength: 6)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func exportMark(for clip: EDLClip) -> some View {
        switch renders[clip.id] {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(StudioTheme.success)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        case .rendering:
            ProgressView().controlSize(.mini).tint(.white)
        case .idle, .none:
            EmptyView()
        }
    }
}
