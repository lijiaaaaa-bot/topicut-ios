// Why: the outcome screen — a capped-height player in the source's own aspect ratio, a table of
// every clip with its full title, and one save action. All titles are readable without selecting
// anything; every clip plays instantly from the source composition; the export (cut, concat,
// burnt subtitles, MP4) happens only when the user saves, with progress shown in the button
// itself. Saving confirms in place with a haptic; only failures interrupt with text.

import LiveSliceCore
import LiveSliceRender
import SwiftUI

struct ClipListView: View {
    @Bindable var session: SliceSession
    @State private var selectedID: String?
    @State private var preview: PreviewState = .loading
    /// Source width/height, learnt from the first preview; 16:9 only until then.
    @State private var sourceAspect: CGFloat = 16 / 9
    @State private var saved: URL?
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var showRationale = false

    var body: some View {
        if let result = session.result, let shown = selection(in: result.document.clips) {
            workbench(result: result, clips: result.document.clips, clip: shown)
        } else {
            ContentUnavailableView("没有可用切片", systemImage: "square.dashed")
                .background(StudioTheme.background)
        }
    }

    /// The clip on screen: the selected one, or the first while nothing has been chosen yet.
    private func selection(in clips: [EDLClip]) -> EDLClip? {
        if let selected = clips.first(where: { $0.id == selectedID }) { return selected }
        return clips.first
    }

    private func workbench(result: SessionResult, clips: [EDLClip], clip: EDLClip) -> some View {
        VStack(spacing: 12) {
            ClipStage(preview: preview, aspect: sourceAspect, sourceURL: result.sourceURL, posterSeconds: clip.startSec)
                .id(clip.id)
                .transition(.opacity)
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical) { height, _ in height * 0.36 }
            if let usage = result.document.llm {
                usageLine(usage, result: result)
            }
            ClipTable(
                sourceURL: result.sourceURL, clips: clips, selectedID: clip.id, renders: displayRenders(clips),
                select: { selectedID = $0; preview = .loading }, showRationale: { showRationale = true }
            )
            .frame(maxHeight: .infinity)
            actions(for: clip)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .background(StudioTheme.background)
        .animation(StudioTheme.motion, value: clip.id)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { session.reset() } label: {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if case .done(let url) = state(of: clip) {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .task(id: clip.id) {
            await buildPreview(result: result, clip: clip)
        }
        .sheet(isPresented: $showRationale) {
            ClipDetailView(clip: clip)
                .preferredColorScheme(.dark)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(StudioTheme.background)
        }
        .alert("保存失败", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            if let saveError { Text(saveError) }
        }
        .sensoryFeedback(.selection, trigger: selectedID)
        .sensoryFeedback(.success, trigger: saved)
    }

    /// What the slicing call consumed: the server's token count, and the charge when the service's
    /// price sheet is known (DeepSeek); other services show tokens only.
    private func usageLine(_ usage: LLMUsage, result: SessionResult) -> some View {
        HStack(spacing: 6) {
            Spacer()
            Text(LLMCost.tokenText(usage))
            if let charge = LLMCost.estimate(usage: usage, slicedWith: result.slicedWith, generatedAt: result.document.generatedAt) {
                Text("·")
                Text(LLMCost.text(charge))
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(StudioTheme.muted)
        .padding(.horizontal, 4)
        .padding(.top, -4)
    }

    @ViewBuilder
    private func actions(for clip: EDLClip) -> some View {
        switch state(of: clip) {
        case .failed(let message):
            Text(message)
                .font(.caption.monospaced())
                .foregroundStyle(.orange)
                .textSelection(.enabled)
                .lineLimit(3)
            Button("重试") { Task { await exportAndSave(clip) } }
                .buttonStyle(PrimaryButtonStyle())
        case .idle, .rendering, .done:
            Button {
                Task { await exportAndSave(clip) }
            } label: {
                saveLabel(for: clip)
            }
            .buttonStyle(PrimaryButtonStyle(tint: isSavedCurrent(clip) ? savedTint : StudioTheme.accentGradient))
            .disabled(isSaving || isExporting(clip) || isSavedCurrent(clip))
            .contentTransition(.symbolEffect(.replace))
            .animation(StudioTheme.motion, value: saved)
        }
    }

    @ViewBuilder
    private func saveLabel(for clip: EDLClip) -> some View {
        switch state(of: clip) {
        case .rendering(let value):
            Label("导出中 \(value.formatted(.percent.precision(.fractionLength(0))))", systemImage: "hourglass")
                .monospacedDigit()
                .contentTransition(.numericText(value: value))
        case .done where isSavedCurrent(clip):
            Label("已保存到相册", systemImage: "checkmark")
        case .idle, .done, .failed:
            if isSaving {
                Label("保存中", systemImage: "arrow.down.circle")
            } else {
                Label("保存到相册", systemImage: "arrow.down.to.line")
            }
        }
    }

    private var savedTint: LinearGradient {
        LinearGradient(colors: [StudioTheme.success, StudioTheme.success.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
    }

    private func state(of clip: EDLClip) -> ClipRenderState {
        guard let stored = session.renders[clip.id] else { return .idle }
        return stored
    }

    private func displayRenders(_ clips: [EDLClip]) -> [String: ClipRenderState] {
        Dictionary(uniqueKeysWithValues: clips.map { ($0.id, state(of: $0)) })
    }

    private func isExporting(_ clip: EDLClip) -> Bool {
        if case .rendering = state(of: clip) { return true }
        return false
    }

    private func isSavedCurrent(_ clip: EDLClip) -> Bool {
        if case .done(let url) = state(of: clip) { return saved == url }
        return false
    }

    /// Builds the playable composition for the shown clip; SwiftUI cancels and re-runs it when the
    /// clip changes. This is the only work a tap on a row triggers. `select` already reset the
    /// state to `.loading` synchronously, so the new stage never starts by playing the previous clip.
    private func buildPreview(result: SessionResult, clip: EDLClip) async {
        preview = .loading
        do {
            let built = try await ClipRenderer().preview(sourceURL: result.sourceURL, clip: clip, cues: result.cues)
            guard !Task.isCancelled else { return }
            if built.renderSize.height > 0 { sourceAspect = built.renderSize.width / built.renderSize.height }
            preview = .ready(built)
        } catch is CancellationError {
        } catch {
            preview = .failed(ErrorText.describe(error))
        }
    }

    /// Exports if the clip has no file yet, then writes it to Photos.
    private func exportAndSave(_ clip: EDLClip) async {
        isSaving = true
        defer { isSaving = false }
        if case .done(let url) = state(of: clip) {
            await save(url)
            return
        }
        await session.render(clip: clip)
        if case .done(let url) = state(of: clip) {
            await save(url)
        }
    }

    private func save(_ url: URL) async {
        do {
            try await PhotoLibrarySaver.save(videoURL: url)
            saved = url
        } catch {
            saveError = ErrorText.describe(error)
        }
    }
}

/// Durations and clock times as people read them, not as timecode.
enum TimeText {
    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) 秒" }
        return "\(total / 60) 分 \(total % 60) 秒"
    }

    /// Compact Chinese duration used on the workbench pills (`48秒`, `1分02秒`, `7分10秒`).
    static func compact(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        if h > 0 { return s == 0 ? "\(h)小时\(m)分" : String(format: "%d小时%d分%02d秒", h, m, s) }
        if m > 0 { return s == 0 ? "\(m)分" : String(format: "%d分%02d秒", m, s) }
        return "\(s)秒"
    }
}