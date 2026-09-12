// Why: the workbench shows the result; this sheet shows why the result looks like that — the
// model's reason, the score, and the exact kept/removed ranges from the EDL. It is read-only on
// purpose: editing the EDL in the app is not implemented, so the UI must not offer it.

import LiveSliceCore
import SwiftUI

struct ClipDetailView: View {
    let clip: EDLClip
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ClipRationaleCard(clip: clip)

                    VStack(alignment: .leading, spacing: 12) {
                        Label("保留 \(clip.segments.count) 段", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(StudioTheme.success)
                        ForEach(Array(clip.segments.enumerated()), id: \.offset) { _, segment in
                            SegmentRow(segment: segment, removed: false)
                        }
                    }
                    .studioCard()

                    if !clip.removedSegments.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("删除 \(clip.removedSegments.count) 段", systemImage: "scissors")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.red)
                            ForEach(Array(clip.removedSegments.enumerated()), id: \.offset) { _, segment in
                                SegmentRow(segment: segment, removed: true)
                            }
                        }
                        .studioCard()
                    }

                    if !clip.tags.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(clip.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(StudioTheme.muted)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(StudioTheme.raised, in: Capsule())
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(StudioTheme.background)
            .navigationTitle("剪辑依据")
            .studioBar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

/// Why the clip exists, in one card: category, score, title, the model's reason, the source range
/// and the kept ranges. The sheet opens with it; on iPad it sits beside the player permanently.
struct ClipRationaleCard: View {
    let clip: EDLClip

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let category = clip.category {
                    Text(category)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(StudioTheme.accent)
                }
                Spacer()
                Text("话题分 \((clip.score * 100).formatted(.number.precision(.fractionLength(0))))")
                    .font(.caption.bold())
                    .foregroundStyle(StudioTheme.success)
            }
            Text(clip.title).font(.headline)
            Text(clip.reason)
                .font(.subheadline)
                .foregroundStyle(StudioTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("原视频 \(TimeText.clock(clip.startSec))–\(TimeText.clock(clip.endSec))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(StudioTheme.muted)
            ClipSegmentBar(clip: clip)
        }
        .studioCard()
    }
}

/// Kept ranges drawn against the clip's own span, so gaps are visible at a glance.
struct ClipSegmentBar: View {
    let clip: EDLClip

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                ForEach(Array(clip.segments.enumerated()), id: \.offset) { _, segment in
                    Capsule()
                        .fill(StudioTheme.success)
                        .frame(width: width(of: segment, in: proxy.size.width))
                        .offset(x: offset(of: segment, in: proxy.size.width))
                }
            }
        }
        .frame(height: 7)
        .accessibilityLabel("保留片段分布")
    }

    private func width(of segment: EDLSegment, in totalWidth: CGFloat) -> CGFloat {
        max(3, totalWidth * (segment.endSec - segment.startSec) / span)
    }

    private func offset(of segment: EDLSegment, in totalWidth: CGFloat) -> CGFloat {
        totalWidth * (segment.startSec - clip.startSec) / span
    }

    private var span: Double {
        max(0.001, clip.endSec - clip.startSec)
    }
}

struct SegmentRow: View {
    let segment: EDLSegment
    let removed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text("\(TimeText.clock(segment.startSec)) → \(TimeText.clock(segment.endSec))")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(removed ? .red : .white)
                Text(TimeText.compact(segment.endSec - segment.startSec))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(StudioTheme.muted)
            }
            if let reason = segment.reason {
                Text(reason).font(.caption).foregroundStyle(StudioTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
