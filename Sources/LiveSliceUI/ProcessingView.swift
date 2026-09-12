// Why: the wait screen. One ring shows the real fraction of the current stage (or spins for the
// LLM call, which has none), a clock shows real elapsed time, and three unlabeled segments show
// position — the stage title above already names the step. Nothing here estimates remaining time.

import SwiftUI

struct ProcessingView: View {
    @Bindable var session: SliceSession

    private var fraction: Double? {
        switch session.stage {
        case .preparingModel(let value), .transcribing(let value): value
        case .slicing, .idle, .awaitingSlice, .ready, .failed: nil
        }
    }

    private var stepIndex: Int {
        switch session.stage {
        case .preparingModel: 0
        case .transcribing: 1
        case .slicing: 2
        case .idle, .awaitingSlice, .ready, .failed: -1
        }
    }

    private var title: String {
        switch session.stage {
        case .preparingModel:
            return "准备语音模型"
        case .transcribing:
            if let label = localeLabel { return "正在转写 · \(label)" }
            return "正在转写"
        case .slicing:
            return "正在找话题和金句"
        case .idle, .awaitingSlice, .ready, .failed:
            return ""
        }
    }

    /// What the spinner is waiting on: one request that returns in one piece, so no fraction exists.
    private func slicingHint(_ service: String) -> String {
        "整段文字已发给 \(service)，等它一次读完再回复。两小时视频通常 1–2 分钟；超过 5 分钟没有回复会报错。"
    }

    private var localeLabel: String? {
        guard let id = session.activeLocaleIdentifier else { return nil }
        return Locale.current.localizedString(forIdentifier: id) ?? id
    }

    var body: some View {
        ZStack {
            GlowBackdrop(intensity: 1.25)
            VStack(spacing: 0) {
                Spacer()
                ZStack {
                    StudioRing(value: fraction, lineWidth: 12)
                        .frame(width: 196, height: 196)
                    ringLabel
                }
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)
                    .padding(.top, 30)
                elapsed
                    .padding(.top, 6)
                if case .slicing = session.stage, let service = session.slicingService {
                    Text(slicingHint(service))
                        .font(.footnote)
                        .foregroundStyle(StudioTheme.muted.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.top, 14)
                        .padding(.horizontal, 12)
                        .transition(.opacity)
                }
                Spacer()
                steps
                Text("请保持 App 打开")
                    .font(.footnote)
                    .foregroundStyle(StudioTheme.muted.opacity(0.7))
                    .padding(.top, 18)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 26)
        }
        .animation(StudioTheme.motion, value: stepIndex)
        .animation(StudioTheme.motion, value: session.activeLocaleIdentifier)
    }

    @ViewBuilder
    private var ringLabel: some View {
        if let fraction {
            Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: fraction))
                .animation(StudioTheme.motion, value: fraction)
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(StudioTheme.accentGradient)
                .symbolEffect(.pulse)
        }
    }

    private var elapsed: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let startedAt = session.startedAt {
                Text(TimeText.clock(context.date.timeIntervalSince(startedAt)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(StudioTheme.muted)
            }
        }
    }

    private var steps: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index < stepIndex ? AnyShapeStyle(StudioTheme.success)
                          : index == stepIndex ? AnyShapeStyle(StudioTheme.accentGradient)
                          : AnyShapeStyle(Color.white.opacity(0.12)))
                    .frame(height: 5)
            }
        }
    }
}
