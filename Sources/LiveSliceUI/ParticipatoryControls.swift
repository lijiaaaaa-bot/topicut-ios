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
        VStack(spacing: 20) {
            TrimTimeline(draft: $draft, sourceURL: sourceURL, onDraft: onDraftTrim)
            actionRow
            completeRow
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(StudioTheme.background)
        .preferredColorScheme(.dark)
        .onChange(of: duration) { _, new in
            draft = TrimDraft(duration: new, originStart: originStart)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(action: onMerge) {
                Label("与下一条合并", systemImage: "arrow.triangle.merge")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(StudioTheme.raised, in: Capsule())
            }
            .disabled(!canMerge)
            .opacity(canMerge ? 1 : 0.4)
            Button(action: dismiss) {
                Label("丢弃", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.38, green: 0.12, blue: 0.14), in: Capsule())
            }
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .buttonStyle(.plain)
    }

    private var completeRow: some View {
        HStack {
            Spacer()
            Button(action: complete) {
                Image(systemName: "checkmark")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(StudioTheme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("完成")
        }
    }

    private func complete() {
        if draft.isDirty { onApplyTrim(draft.leading, draft.trailing) }
        dismiss()
    }
}
