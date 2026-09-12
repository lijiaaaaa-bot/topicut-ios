// Why: workbench controls for Topicut 2.0 — drag+pinch 9:16 framing, live draft trim, merge.
// Slice / look studios are separate full-screen environments opened from the toolbar (ADR-0029).

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

/// Live draft trim: sliders rebuild the stage; 应用裁切 writes the EDL.
struct ClipTrimBar: View {
    let duration: Double
    let onDraft: (_ leading: Double, _ trailing: Double) -> Void
    let onApply: (_ leading: Double, _ trailing: Double) -> Void
    @State private var leading = 0.0
    @State private var trailing = 0.0

    private var maxEdge: Double { max(0, (duration - 0.5) / 2) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("头 \(Int(leading))s").font(.caption2).foregroundStyle(StudioTheme.muted).frame(width: 52, alignment: .leading)
                Slider(value: $leading, in: 0...maxEdge, step: 0.5)
                    .onChange(of: leading) { _, v in onDraft(v, trailing) }
            }
            HStack {
                Text("尾 \(Int(trailing))s").font(.caption2).foregroundStyle(StudioTheme.muted).frame(width: 52, alignment: .leading)
                Slider(value: $trailing, in: 0...maxEdge, step: 0.5)
                    .onChange(of: trailing) { _, v in onDraft(leading, v) }
            }
            Button("应用裁切") { onApply(leading, trailing) }
                .font(.caption.weight(.semibold))
                .disabled(leading == 0 && trailing == 0)
        }
        .padding(12)
        .background(StudioTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: duration) { _, _ in
            leading = 0
            trailing = 0
        }
    }
}

struct ClipMergeButton: View {
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("与下一条合并", systemImage: "arrow.triangle.merge")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// Trim + merge only — presented in a half-sheet so the workbench stays preview/list/save.
struct ClipEditStack: View {
    let duration: Double
    let canMerge: Bool
    let onDraftTrim: (_ leading: Double, _ trailing: Double) -> Void
    let onApplyTrim: (_ leading: Double, _ trailing: Double) -> Void
    let onMerge: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ClipTrimBar(duration: duration, onDraft: onDraftTrim, onApply: onApplyTrim)
            ClipMergeButton(enabled: canMerge, action: onMerge)
        }
    }
}

/// Half-sheet chrome for head/tail trim + merge. Draft preview stays on the workbench stage.
struct ClipEditSheet: View {
    let title: String
    let duration: Double
    let canMerge: Bool
    let onDraftTrim: (_ leading: Double, _ trailing: Double) -> Void
    let onApplyTrim: (_ leading: Double, _ trailing: Double) -> Void
    let onMerge: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("裁切这条")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button("完成", action: dismiss)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(StudioTheme.accent)
            }
            Text(title)
                .font(.subheadline)
                .foregroundStyle(StudioTheme.muted)
                .lineLimit(2)
            Text("拖动即在上方试看；点「应用裁切」才写入。关掉未应用的改动会丢弃。")
                .font(.caption)
                .foregroundStyle(StudioTheme.muted)
            ClipEditStack(
                duration: duration, canMerge: canMerge,
                onDraftTrim: onDraftTrim, onApplyTrim: onApplyTrim, onMerge: onMerge
            )
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(StudioTheme.background)
        .preferredColorScheme(.dark)
    }
}
