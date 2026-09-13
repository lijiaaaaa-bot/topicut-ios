// Why: workbench shell — preview, 话题/金句, title rows, green 保存到相册. Long-press the
// stage to trim; look is the remaining glass toolbar icon (ADR-0030/0031).

import LiveSliceCore
import LiveSliceRender
import SwiftUI

struct ClipListView: View {
    @Bindable var session: SliceSession
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State var tab: ResultTab = .topics
    @State var selectedID: String?
    @State var preview: PreviewState = .loading
    /// Source width/height, learnt from the first preview; 16:9 only until then.
    @State var sourceAspect: CGFloat = 16 / 9
    @State var saved: URL?
    @State var saveError: String?
    @State var isSaving = false
    @State var showRationale = false
    @State var confirmRetranscribe = false
    @State var openLookStudio = false
    @State var openSliceStudio = false
    @State var openClipEdit = false
    @Namespace var editMorph

    var isWide: Bool { sizeClass == .regular }

    var body: some View {
        if let result = session.result, let shown = selection(in: result.document) {
            workbench(result: result, clips: tab.clips(in: result.document), clip: shown)
        } else {
            ContentUnavailableView("没有可用切片", systemImage: "square.dashed")
                .background(StudioTheme.background)
        }
    }

    /// The clip on screen: the selected one in the current tab, else the tab's first; while the
    /// stale-highlights panel is up the stage keeps the first topic rather than going dark.
    private func selection(in document: EDLDocument) -> EDLClip? {
        let clips = tab.clips(in: document) ?? document.clips
        if let selected = clips.first(where: { $0.id == selectedID }) { return selected }
        return clips.first
    }

    private func workbench(result: SessionResult, clips: [EDLClip]?, clip: EDLClip) -> some View {
        withWorkbenchChrome(result: result, clip: clip) {
            Group {
                if isWide {
                    wide(result: result, clips: clips, clip: clip)
                } else {
                    narrow(result: result, clips: clips, clip: clip)
                }
            }
        }
    }

    private func narrow(result: SessionResult, clips: [EDLClip]?, clip: EDLClip) -> some View {
        VStack(spacing: 10) {
            stage(result: result, clip: clip)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 260)
            ResultTabBar(
                document: result.document, slicedWith: result.slicedWith, tab: $tab,
                onReslice: { openSliceStudio = true }, sliceTasteStale: session.sliceTasteStale
            )
            list(result: result, clips: clips, clip: clip, rationaleTap: { showRationale = true })
            actionRow(result: result, clips: clips, clip: clip)
        }
    }

    /// iPad: landscape puts the whole left column beside the lists; portrait keeps the player on
    /// top and splits the rest — actions and rationale left, lists right.
    private func wide(result: SessionResult, clips: [EDLClip]?, clip: EDLClip) -> some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            let lists = VStack(spacing: 12) {
                ResultTabBar(
                    document: result.document, slicedWith: result.slicedWith, tab: $tab,
                    onReslice: { openSliceStudio = true }, sliceTasteStale: session.sliceTasteStale
                )
                list(result: result, clips: clips, clip: clip, rationaleTap: nil)
            }
            let side = VStack(alignment: .leading, spacing: 14) {
                actionRow(result: result, clips: clips, clip: clip)
                ClipRationaleCard(clip: clip)
                    .id(clip.id)
                    .transition(.opacity)
                Spacer(minLength: 0)
            }
            if landscape {
                HStack(alignment: .top, spacing: 24) {
                    VStack(spacing: 14) {
                        stage(result: result, clip: clip)
                            .frame(maxHeight: proxy.size.height * 0.56)
                        side
                    }
                    .frame(width: proxy.size.width * 0.58)
                    lists
                }
            } else {
                VStack(spacing: 14) {
                    stage(result: result, clip: clip)
                        .frame(maxHeight: proxy.size.height * 0.42)
                    HStack(alignment: .top, spacing: 24) {
                        side.frame(width: proxy.size.width * 0.44)
                        lists
                    }
                }
            }
        }
    }

    private func stage(result: SessionResult, clip: EDLClip) -> some View {
        ClipStage(
            preview: preview, aspect: sourceAspect, sourceURL: result.sourceURL, posterSeconds: clip.startSec,
            captionStyle: session.captionStyle, captionTune: session.captionTune, clipID: clip.id,
            cropFocus: session.cropFocus(for: clip.id), cropZoom: session.cropZoom(for: clip.id),
            showCropPad: false
        )
        .id(clip.id)
        .transition(.opacity)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in openClipEdit = true }
        )
        .workbenchEditSource(namespace: editMorph)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("裁切与合并")) { openClipEdit = true }
    }

    /// Topic/highlight table, or the re-slice offer when highlights are absent.
    @ViewBuilder
    private func list(result: SessionResult, clips: [EDLClip]?, clip: EDLClip, rationaleTap: (() -> Void)?) -> some View {
        if let clips {
            ClipTable(
                sourceURL: result.sourceURL, clips: clips, selectedID: clip.id, renders: displayRenders(clips),
                select: selectClip, showRationale: rationaleTap
            )
            .frame(maxHeight: .infinity)
            .transition(.opacity)
            .id(tab)
        } else {
            StaleHighlightsPanel(document: result.document, slicedWith: result.slicedWith) {
                Task { await session.reslice() }
            }
        }
    }

    private func actionRow(result: SessionResult, clips: [EDLClip]?, clip: EDLClip) -> some View {
        VStack(spacing: 8) { actions(for: clip) }
            .disabled(clips == nil)
            .opacity(clips == nil ? 0.4 : 1)
    }

    @ViewBuilder
    private func actions(for clip: EDLClip) -> some View {
        switch renderState(of: clip) {
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
            .buttonStyle(SaveBarButtonStyle(tint: isSavedCurrent(clip) ? StudioTheme.success.opacity(0.82) : StudioTheme.success))
            .disabled(isSaving || isExporting(clip) || isSavedCurrent(clip))
            .contentTransition(.symbolEffect(.replace))
            .animation(StudioTheme.motion, value: saved)
        }
    }

    @ViewBuilder
    private func saveLabel(for clip: EDLClip) -> some View {
        switch renderState(of: clip) {
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
                Label(ExportLookText.saveTitle(style: session.captionStyle, position: session.captionPosition, framing: session.framingMode, tune: session.captionTune), systemImage: "photo")
            }
        }
    }

    private func selectClip(_ id: String) {
        selectedID = id
        preview = .loading
    }

    func renderState(of clip: EDLClip) -> ClipRenderState {
        guard let stored = session.renders[clip.id] else { return .idle }
        return stored
    }

    private func displayRenders(_ clips: [EDLClip]) -> [String: ClipRenderState] {
        Dictionary(uniqueKeysWithValues: clips.map { ($0.id, renderState(of: $0)) })
    }

    private func isExporting(_ clip: EDLClip) -> Bool {
        if case .rendering = renderState(of: clip) { return true }
        return false
    }

    private func isSavedCurrent(_ clip: EDLClip) -> Bool {
        if case .done(let url) = renderState(of: clip) { return saved == url }
        return false
    }

}
