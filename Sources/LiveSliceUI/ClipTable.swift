// Why: workbench clip list — phone filmstrip matching the mock, iPad keep the title rows.
// Titles stay here, never as ResultTabBar chips (ADR-0030 / 0031).

import LiveSliceCore
import SwiftUI

enum ClipListLayout {
    case rows
    case filmstrip
}

/// Number, first frame, title, duration, export mark. Tap plays; ⋮ opens 依据 on phone rows.
struct ClipTable: View {
    let sourceURL: URL
    let clips: [EDLClip]
    let selectedID: String
    let renders: [String: ClipRenderState]
    let select: (String) -> Void
    /// Tap on the selected row; nil where the rationale is already on screen (iPad).
    let showRationale: (() -> Void)?
    var layout: ClipListLayout = .rows

    var body: some View {
        switch layout {
        case .rows: rowList
        case .filmstrip: filmstrip
        }
    }

    private var rowList: some View {
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

    private var filmstrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TimeText.filmstripHeading(clips.count))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(clips, id: \.id) { clip in
                            card(clip)
                                .id(clip.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onChange(of: selectedID) { _, id in
                    withAnimation(StudioTheme.motion) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private func card(_ clip: EDLClip) -> some View {
        let on = clip.id == selectedID
        return Button {
            if clip.id == selectedID {
                showRationale?()
            } else {
                withAnimation(StudioTheme.motion) { select(clip.id) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    ClipPoster(url: sourceURL, seconds: clip.startSec, maximumSize: CGSize(width: 240, height: 160))
                        .frame(width: 92, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    if on {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, StudioTheme.accent)
                            .padding(4)
                    }
                    Text(TimeText.clock(clip.keptDurationSec))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(4)
                }
                .frame(width: 92, height: 60)
                Text(clip.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(TimeText.range(from: clip.startSec, to: clip.endSec))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(StudioTheme.muted)
                    .lineLimit(1)
            }
            .frame(width: 92, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel(clip.title)
        .accessibilityAddTraits(on ? .isSelected : [])
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
