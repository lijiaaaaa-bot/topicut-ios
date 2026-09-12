// Why: thumb-sized in/out handles on a source filmstrip, so one-handed drag sets the
// selected clip's start and end without pixel-precise tapping. The bar is kept (green)
// versus not kept (red); times on the handles are the live range.

import LiveSliceCore
import SwiftUI

struct TrimTimelineView: View {
    let sourceURL: URL
    let clip: EDLClip
    let window: TrimWindow
    @Binding var startSec: Double
    @Binding var endSec: Double
    var onScrub: (Double) -> Void
    var onEnded: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("\(TimeText.clock(startSec)) – \(TimeText.clock(endSec))")
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
            KeepDiscardBar(clip: clip, startSec: startSec, endSec: endSec, window: window)
            ZStack {
                FilmstripTrack(sourceURL: sourceURL, window: window)
                TrimHandleLayer(
                    window: window, startSec: $startSec, endSec: $endSec,
                    onScrub: onScrub, onEnded: onEnded
                )
            }
            .frame(height: 88)
            TickRow(window: window)
        }
    }
}

struct KeepDiscardBar: View {
    let clip: EDLClip
    let startSec: Double
    let endSec: Double
    let window: TrimWindow

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.red.opacity(0.82))
                ForEach(Array(keptRanges.enumerated()), id: \.offset) { _, range in
                    Capsule()
                        .fill(StudioTheme.success)
                        .frame(width: width(of: range, in: proxy.size.width), height: 6)
                        .offset(x: offset(of: range, in: proxy.size.width))
                }
            }
        }
        .frame(height: 6)
        .accessibilityLabel("\(TimeText.clock(startSec)) \(TimeText.clock(endSec))")
    }

    private var keptRanges: [(Double, Double)] {
        var ranges: [(Double, Double)] = clip.segments.compactMap { segment in
            let lo = max(segment.startSec, startSec, window.startSec)
            let hi = min(segment.endSec, endSec, window.endSec)
            return hi > lo + 0.0005 ? (lo, hi) : nil
        }
        if startSec < clip.startSec {
            let hi = min(clip.startSec, endSec, window.endSec)
            let lo = max(startSec, window.startSec)
            if hi > lo + 0.0005 { ranges.append((lo, hi)) }
        }
        if endSec > clip.endSec {
            let lo = max(clip.endSec, startSec, window.startSec)
            let hi = min(endSec, window.endSec)
            if hi > lo + 0.0005 { ranges.append((lo, hi)) }
        }
        return ranges
    }

    private func width(of range: (Double, Double), in total: CGFloat) -> CGFloat {
        max(3, window.position(of: range.1, width: total) - window.position(of: range.0, width: total))
    }

    private func offset(of range: (Double, Double), in total: CGFloat) -> CGFloat {
        window.position(of: range.0, width: total)
    }
}

struct FilmstripTrack: View {
    let sourceURL: URL
    let window: TrimWindow

    var body: some View {
        GeometryReader { proxy in
            let count = max(6, Int(proxy.size.width / 48))
            HStack(spacing: 1) {
                ForEach(window.ticks(count: count), id: \.self) { time in
                    ClipPoster(
                        url: sourceURL, seconds: time, maximumSize: CGSize(width: 200, height: 140),
                        contentMode: .fill
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct TrimHandleLayer: View {
    let window: TrimWindow
    @Binding var startSec: Double
    @Binding var endSec: Double
    var onScrub: (Double) -> Void
    var onEnded: () -> Void

    private let minimum: Double = 0.1

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            handle(time: startSec, isStart: true, width: width, height: proxy.size.height)
            handle(time: endSec, isStart: false, width: width, height: proxy.size.height)
        }
        .coordinateSpace(name: "trim-track")
    }

    private func handle(time: Double, isStart: Bool, width: CGFloat, height: CGFloat) -> some View {
        let x = window.position(of: time, width: width)
        return TrimHandle(time: time)
            .position(x: x, y: height / 2)
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("trim-track"))
                    .onChanged { value in move(to: value.location.x, width: width, isStart: isStart) }
                    .onEnded { _ in onEnded() }
            )
    }

    private func move(to position: CGFloat, width: CGFloat, isStart: Bool) {
        let time = window.time(at: position, width: width)
        if isStart {
            startSec = min(time, endSec - minimum)
        } else {
            endSec = max(time, startSec + minimum)
        }
        onScrub(isStart ? startSec : endSec)
    }
}

struct TrimHandle: View {
    let time: Double

    var body: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(StudioTheme.accent)
                .frame(width: 3, height: 72)
            Text(TimeText.clock(time))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
        }
        .overlay(alignment: .top) {
            Circle()
                .fill(StudioTheme.accent)
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .frame(width: 28, height: 28)
                .offset(y: 22)
        }
        .frame(width: 56, height: 88)
        .contentShape(Rectangle())
        .accessibilityLabel(TimeText.clock(time))
    }
}

struct TickRow: View {
    let window: TrimWindow

    var body: some View {
        let marks = window.ticks(count: 5)
        HStack {
            ForEach(Array(marks.enumerated()), id: \.offset) { index, time in
                Text(TimeText.clock(time))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(StudioTheme.muted)
                if index + 1 < marks.count { Spacer(minLength: 0) }
            }
        }
    }
}
