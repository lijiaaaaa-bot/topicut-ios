// Why: workbench chrome — quiet edit + look toolbar icons, edit half-sheet, look/slice covers.
// Slice re-entry is the tab-bar overflow, not a third toolbar glyph (ADR-0030).

import LiveSliceCore
import LiveSliceRender
import SwiftUI

extension ClipListView {
    /// Chrome around the narrow/wide layout: toolbar icons open studios / clip edit; covers are full-screen on iOS.
    @ViewBuilder
    func withWorkbenchChrome<Content: View>(
        result: SessionResult, clip: EDLClip, @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .onChange(of: tab) { _, _ in selectedID = nil; preview = .loading }
            .onChange(of: session.framingMode) { _, _ in preview = .loading }
            .onChange(of: openClipEdit) { _, open in
                if !open {
                    session.clearDraftTrim()
                    preview = .loading
                }
            }
            .padding(.horizontal, isWide ? 24 : 16)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .background(StudioTheme.background)
            .animation(StudioTheme.motion, value: clip.id)
            .toolbar { workbenchToolbar }
            .modifier(WorkbenchStudioCovers(
                result: result,
                clip: clip,
                openLook: $openLookStudio,
                openSlice: $openSliceStudio,
                confirmRetranscribe: $confirmRetranscribe,
                session: session
            ))
            .task(id: previewTaskID(clip)) {
                await buildPreview(result: result, clip: clip)
            }
            .sheet(isPresented: $showRationale) {
                ClipDetailView(clip: clip)
                    .preferredColorScheme(.dark)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(StudioTheme.background)
            }
            .sheet(isPresented: $openClipEdit) {
                clipEditSheet(result: result, clip: clip)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(StudioTheme.background)
            }
            .alert("保存失败", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                if let saveError { Text(saveError) }
            }
            .confirmationDialog("重新转写这个视频？", isPresented: $confirmRetranscribe, titleVisibility: .visible) {
                Button("重新转写") { Task { await session.retranscribe() } }
            } message: {
                Text("在本机重新识别语音，得到逐词时间。话题、金句和已导出的文件都保留，不会再调用 AI 服务。")
            }
            .sensoryFeedback(.selection, trigger: selectedID)
            .sensoryFeedback(.success, trigger: saved)
    }

    @ToolbarContentBuilder
    var workbenchToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button { session.reset() } label: {
                Image(systemName: "chevron.left")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { openClipEdit = true } label: {
                Image(systemName: "scissors")
            }
            .accessibilityLabel("裁切与合并")
            Button { openLookStudio = true } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel("成片样式")
        }
    }

    func clipEditSheet(result: SessionResult, clip: EDLClip) -> some View {
        let clips: [EDLClip]
        if let listed = tab.clips(in: result.document) {
            clips = listed
        } else {
            clips = []
        }
        let canMerge: Bool
        if let index = clips.firstIndex(where: { $0.id == clip.id }) {
            canMerge = index + 1 < clips.count
        } else {
            canMerge = false
        }
        return ClipEditSheet(
            duration: clip.endSec - clip.startSec,
            originStart: clip.startSec,
            sourceURL: result.sourceURL,
            canMerge: canMerge,
            onDraftTrim: { leading, trailing in
                session.setDraftTrim(clipID: clip.id, leading: leading, trailing: trailing)
                preview = .loading
            },
            onApplyTrim: { leading, trailing in
                session.trimClip(id: clip.id, leading: leading, trailing: trailing)
                preview = .loading
            },
            onMerge: {
                session.mergeWithNext(id: clip.id)
                openClipEdit = false
                preview = .loading
            },
            dismiss: { openClipEdit = false }
        )
        .id(clip.id)
    }
}

/// Slice + look full-screen covers bound to the workbench session.
private struct WorkbenchStudioCovers: ViewModifier {
    let result: SessionResult
    let clip: EDLClip
    @Binding var openLook: Bool
    @Binding var openSlice: Bool
    @Binding var confirmRetranscribe: Bool
    @Bindable var session: SliceSession

    func body(content: Content) -> some View {
        content
            .studioCover(isPresented: $openLook) {
                ExportLookStudio(
                    style: $session.captionStyle, position: $session.captionPosition,
                    tune: $session.captionTune, framing: $session.framingMode,
                    sourceURL: result.sourceURL, clip: session.clipForPreview(clip),
                    cues: result.cues, words: result.words,
                    cropFocus: session.cropFocus(for: clip.id),
                    cropZoom: session.cropZoom(for: clip.id),
                    onCropFocus: { session.setCropFocus($0, for: clip.id) },
                    onCropZoom: { session.setCropZoom($0, for: clip.id) },
                    onCropReset: { session.clearCropOverride(for: clip.id) },
                    hasWords: result.words?.isEmpty == false,
                    retranscribe: { openLook = false; confirmRetranscribe = true },
                    onDescribe: { prompt in try await session.describeLook(prompt) },
                    dismiss: { openLook = false }
                )
            }
            .studioCover(isPresented: $openSlice) {
                SliceStudio(
                    taste: $session.slicingTaste,
                    info: AwaitingSliceInfo(
                        projectID: result.projectID, sourceURL: result.sourceURL, cueCount: result.cues.count,
                        localeIdentifier: result.localeIdentifier, hasWords: result.words != nil
                    ),
                    sliceError: nil,
                    onConfirm: {
                        openSlice = false
                        Task { await session.resliceFromTaste() }
                    },
                    onCancel: { openSlice = false }
                )
            }
    }
}
