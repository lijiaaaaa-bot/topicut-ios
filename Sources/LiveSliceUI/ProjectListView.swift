// Why: saved projects on the idle screen, so a video processed once is one tap away forever.
// Each row is the project's own first frame, the first clip title, and a real status (clip count
// and date, or which step is still missing). Swipe to delete; delete failures surface via the session.

import LiveSliceCore
import SwiftUI

struct ProjectListView: View {
    @Bindable var session: SliceSession
    let sourceURL: (ProjectRecord) -> URL

    var body: some View {
        List {
            ForEach(session.projects) { record in
                Button {
                    Task { await session.open(record) }
                } label: {
                    ProjectRow(record: record, sourceURL: sourceURL(record))
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(.white.opacity(0.08))
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { session.delete(record) } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(StudioTheme.motion, value: session.projects.map(\.id))
    }
}

private struct ProjectRow: View {
    let record: ProjectRecord
    let sourceURL: URL

    var body: some View {
        HStack(spacing: 14) {
            ClipPoster(url: sourceURL, seconds: posterSeconds, maximumSize: CGSize(width: 240, height: 240))
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title ?? record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(record.isSliced ? StudioTheme.muted : .orange)
            }
            Spacer(minLength: 8)
            Image(systemName: record.isSliced ? "chevron.right" : "arrow.clockwise")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(StudioTheme.muted)
        }
        .contentShape(Rectangle())
    }

    private var posterSeconds: Double {
        if let first = record.document?.clips.first { return first.startSec }
        return 1
    }

    private var status: String {
        let date = record.createdAt.formatted(.dateTime.month().day())
        if record.isSliced {
            if let quotes = record.document?.highlights?.count { return "\(record.clipCount) 话题 · \(quotes) 金句 · \(date)" }
            return "\(record.clipCount) 话题 · \(date)"
        }
        if record.isTranscribed { return "已转写，点击继续找话题" }
        return "未处理，点击继续"
    }
}
