// Why: the workbench sheet is where a clip's in/out change, it is dropped, or it is
// joined to the next one. The EDL is rewritten in memory and written back on 完成;
// ASR and DeepSeek are not run again.

import LiveSliceCore
import SwiftUI

struct ClipDetailView: View {
    let sourceURL: URL
    var onScrub: (Double) -> Void
    var onPreview: (EDLClip?) -> Void
    var onCommit: (EDLDocument, Set<String>, String?) throws -> Void

    @State private var editor: EDLEditor
    @State private var startSec: Double
    @State private var endSec: Double
    @State private var editError: String?
    @State private var successTick = 0
    @State private var discardTick = 0
    @Environment(\.dismiss) private var dismiss

    init(
        editor: EDLEditor, sourceURL: URL,
        onScrub: @escaping (Double) -> Void,
        onPreview: @escaping (EDLClip?) -> Void,
        onCommit: @escaping (EDLDocument, Set<String>, String?) throws -> Void
    ) {
        self.sourceURL = sourceURL
        self.onScrub = onScrub
        self.onPreview = onPreview
        self.onCommit = onCommit
        _editor = State(initialValue: editor)
        _startSec = State(initialValue: editor.currentClip?.startSec ?? editor.sourceStart)
        _endSec = State(initialValue: editor.currentClip?.endSec ?? editor.sourceEnd)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let clip = editor.currentClip {
                    TrimTimelineView(
                        sourceURL: sourceURL, clip: clip, window: editor.trimWindow,
                        startSec: $startSec, endSec: $endSec,
                        onScrub: onScrub, onEnded: applyTrim
                    )
                    .padding(.top, 8)
                }
                Spacer(minLength: 0)
                actions
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .background(StudioTheme.background)
            .navigationTitle("修剪视频片段")
            .studioBar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: commit)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(StudioTheme.accent)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            .alert("无法编辑", isPresented: Binding(
                get: { editError != nil },
                set: { if !$0 { editError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                if let editError { Text(editError) }
            }
            .sensoryFeedback(.selection, trigger: Int(startSec.rounded()) * 1_000 + Int(endSec.rounded()))
            .sensoryFeedback(.success, trigger: successTick)
            .sensoryFeedback(.warning, trigger: discardTick)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 12) {
            if editor.canMergeWithNext {
                Button {
                    if apply({ try $0.mergeWithNext() }) { successTick += 1 }
                } label: {
                    Label("与下一条合并", systemImage: "puzzlepiece.extension")
                }
                .buttonStyle(WorkbenchActionStyle(fill: Color.white.opacity(0.12)))
            }
            if editor.currentClip != nil {
                Button {
                    if apply({ try $0.discardCurrent() }) { discardTick += 1 }
                } label: {
                    Label("丢弃", systemImage: "trash")
                }
                .buttonStyle(WorkbenchActionStyle(fill: Color(red: 0.55, green: 0.12, blue: 0.16)))
            }
        }
    }

    private func applyTrim() {
        _ = apply { try $0.trim(start: startSec, end: endSec) }
    }

    private func commit() {
        do {
            try onCommit(editor.document, editor.touchedIDs, editor.clipID)
            successTick += 1
            dismiss()
        } catch {
            editError = ErrorText.describe(error)
        }
    }

    private func apply(_ body: (inout EDLEditor) throws -> Void) -> Bool {
        do {
            var next = editor
            try body(&next)
            editor = next
            if let clip = next.currentClip {
                startSec = clip.startSec
                endSec = clip.endSec
            }
            onPreview(next.currentClip)
            return true
        } catch {
            editError = ErrorText.describe(error)
            return false
        }
    }
}
