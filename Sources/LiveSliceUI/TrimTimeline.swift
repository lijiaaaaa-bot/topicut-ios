// Why: edit-sheet trim geometry — large (≥44pt) handles, fail-closed clamp, draft only
// until 完成 writes the EDL. No silent over-trim past the kept floor (ADR-0030).

import SwiftUI

/// Head/tail window on one clip. `leading`/`trailing` are seconds cut from the kept span.
struct TrimDraft: Equatable, Sendable {
    var leading: Double
    var trailing: Double
    let duration: Double
    let originStart: Double
    let minimumKept: Double

    init(
        duration: Double,
        originStart: Double,
        leading: Double = 0,
        trailing: Double = 0,
        minimumKept: Double = 0.5
    ) {
        self.duration = duration
        self.originStart = originStart
        self.minimumKept = minimumKept
        let keptFloor = min(max(0, minimumKept), max(0, duration))
        let maxTrim = max(0, duration - keptFloor)
        let head = min(max(0, leading), maxTrim)
        self.leading = head
        self.trailing = min(max(0, trailing), max(0, maxTrim - head))
    }

    var startTime: Double { originStart + leading }
    var endTime: Double { originStart + duration - trailing }
    var kept: Double { max(0, duration - leading - trailing) }
    var isDirty: Bool { leading > 0 || trailing > 0 }

    var startFraction: Double {
        guard duration > 0 else { return 0 }
        return leading / duration
    }

    var endFraction: Double {
        guard duration > 0 else { return 1 }
        return (duration - trailing) / duration
    }

    mutating func moveStart(fraction: Double) {
        let raw = fraction * duration
        let maxLeading = max(0, duration - trailing - minimumKept)
        leading = min(max(0, raw), maxLeading)
    }

    mutating func moveEnd(fraction: Double) {
        let raw = fraction * duration
        let minEnd = leading + minimumKept
        let end = min(max(minEnd, raw), duration)
        trailing = max(0, duration - end)
    }
}

/// Filmstrip + two thumb-sized handles. Dragging updates the draft; the parent owns apply/discard.
struct TrimTimeline: View {
    @Binding var draft: TrimDraft
    let sourceURL: URL
    var onDraft: (_ leading: Double, _ trailing: Double) -> Void

    var body: some View {
        VStack(spacing: 10) {
            timeline
            labels
        }
        .onChange(of: draft) { _, new in onDraft(new.leading, new.trailing) }
    }

    private var timeline: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let inset = Self.handleHit / 2
            let usable = max(width - inset * 2, 1)
            let left = inset + draft.startFraction * usable
            let right = inset + draft.endFraction * usable
            ZStack(alignment: .leading) {
                filmstrip
                    .frame(height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                selection(left: left, right: right)
                handle(at: left, move: { draft.moveStart(fraction: ($0 - inset) / usable) })
                handle(at: right, move: { draft.moveEnd(fraction: ($0 - inset) / usable) })
            }
            .coordinateSpace(.named("trim"))
        }
        .frame(height: 64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("裁切范围")
        .accessibilityValue("\(TimeText.clock(draft.startTime)) 到 \(TimeText.clock(draft.endTime))")
    }

    private var filmstrip: some View {
        HStack(spacing: 2) {
            ForEach(frameSeconds, id: \.self) { seconds in
                ClipPoster(
                    url: sourceURL, seconds: seconds, maximumSize: CGSize(width: 180, height: 120)
                )
            }
        }
    }

    private var frameSeconds: [Double] {
        let count = 5
        guard count > 1, draft.duration > 0 else { return [draft.originStart] }
        return (0..<count).map { index in
            draft.originStart + draft.duration * Double(index) / Double(count - 1)
        }
    }

    private func selection(left: CGFloat, right: CGFloat) -> some View {
        let span = max(right - left, 0)
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(StudioTheme.accent, lineWidth: 2)
            .frame(width: span, height: 56)
            .offset(x: left)
            .allowsHitTesting(false)
    }

    static let handleHit: CGFloat = 44

    private func handle(at x: CGFloat, move: @escaping (CGFloat) -> Void) -> some View {
        Circle()
            .fill(StudioTheme.accent)
            .frame(width: 18, height: 18)
            .frame(width: Self.handleHit, height: Self.handleHit)
            .contentShape(Circle())
            .position(x: x, y: 32)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("trim"))
                    .onChanged { value in move(value.location.x) }
            )
            .accessibilityAddTraits(.isButton)
    }

    private var labels: some View {
        HStack {
            Text(TimeText.clock(draft.startTime))
            Spacer()
            Text(TimeText.clock(draft.endTime))
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(StudioTheme.muted)
    }
}
