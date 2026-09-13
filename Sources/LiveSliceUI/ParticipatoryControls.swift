// Why: Topicut 2.0 participatory chrome — 9:16 crop pad (look studio) and the edit half-sheet
// (large-handle trim, merge, 丢弃, 完成). Workbench itself stays preview/list/save (ADR-0030).

import LiveSliceCore
import LiveSliceRender
import SwiftUI

/// Drag to move focus; pinch to tighten the 9:16 window. Preview rebuilds from the parent.
struct CropFocusPad: View {
    let focus: CGPoint?
    let zoom: CGFloat
    let onFocus: (CGPoint) -> Void
    let onZoom: (CGFloat) -> Void
    let onReset: () -> Void
    @State private var pinchBase: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let point = focus ?? CGPoint(x: 0.5, y: 0.5)
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = min(1, max(0, value.location.x / max(proxy.size.width, 1)))
                                let y = min(1, max(0, value.location.y / max(proxy.size.height, 1)))
                                onFocus(CGPoint(x: x, y: y))
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { scale in
                                onZoom(min(3, max(1, pinchBase * scale)))
                            }
                            .onEnded { _ in pinchBase = zoom }
                    )
                Circle()
                    .strokeBorder(.white, lineWidth: 2)
                    .background(Circle().fill(StudioTheme.accent.opacity(0.85)))
                    .frame(width: 22, height: 22)
                    .position(x: point.x * proxy.size.width, y: point.y * proxy.size.height)
                    .allowsHitTesting(false)
                if zoom > 1.05 {
                    Text(String(format: "%.1f×", zoom))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.45), in: Capsule())
                        .position(x: proxy.size.width - 36, y: proxy.size.height - 28)
                }
            }
            .onAppear { pinchBase = zoom }
            .onChange(of: zoom) { _, new in pinchBase = new }
        }
        .overlay(alignment: .topTrailing) {
            Button("跟脸", action: onReset)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.55), in: Capsule())
                .foregroundStyle(.white)
                .padding(8)
        }
        .accessibilityLabel("拖动与捏合调整竖屏取景")
    }
}

/// Half-sheet: filmstrip trim, merge, discard draft, or 完成 to write the EDL.
struct ClipEditSheet: View {
    let duration: Double
    let originStart: Double
    let sourceURL: URL
    let canMerge: Bool
    let onDraftTrim: (_ leading: Double, _ trailing: Double) -> Void
    let onApplyTrim: (_ leading: Double, _ trailing: Double) -> Void
    let onMerge: () -> Void
    let dismiss: () -> Void

    @State private var draft: TrimDraft

    init(
        duration: Double,
        originStart: Double,
        sourceURL: URL,
        canMerge: Bool,
        onDraftTrim: @escaping (_ leading: Double, _ trailing: Double) -> Void,
        onApplyTrim: @escaping (_ leading: Double, _ trailing: Double) -> Void,
        onMerge: @escaping () -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.duration = duration
        self.originStart = originStart
        self.sourceURL = sourceURL
        self.canMerge = canMerge
        self.onDraftTrim = onDraftTrim
        self.onApplyTrim = onApplyTrim
        self.onMerge = onMerge
        self.dismiss = dismiss
        _draft = State(initialValue: TrimDraft(duration: duration, originStart: originStart))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            TrimTimeline(draft: $draft, sourceURL: sourceURL, onDraft: onDraftTrim)
            actionRow
            Text("拖动修剪手柄调整入点和出点")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: duration) { _, new in
            draft = TrimDraft(duration: new, originStart: originStart)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("编辑 EDL")
                    .font(.title3.weight(.semibold))
                Text("修剪片段 · 与下一条合并")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Label("时间线", systemImage: "timeline.selection")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .workbenchGlassCapsule()
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button(action: onMerge) {
                Label("与下一条合并", systemImage: "arrow.triangle.merge")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .disabled(!canMerge)
            .opacity(canMerge ? 1 : 0.4)
            .workbenchGlassCapsule()
            Button(role: .destructive, action: dismiss) {
                Label("丢弃", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .foregroundStyle(.red)
            .workbenchGlassCapsule()
            Button(action: complete) {
                Label("完成", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .foregroundStyle(.white)
                    .background(StudioTheme.accent, in: Capsule())
            }
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.plain)
    }

    private func complete() {
        if draft.isDirty { onApplyTrim(draft.leading, draft.trailing) }
        dismiss()
    }
}
