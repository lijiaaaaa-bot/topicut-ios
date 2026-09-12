// Why: ADR-0027/0029 — 成片 look is a phone-first studio: live clip preview owns the screen;
// presets are cards; knobs sit under a short tab strip. Workbench opens this via toolbar.

import LiveSliceCore
import LiveSliceRender
import SwiftUI

struct ExportLookStudio: View {
    @Binding var style: CaptionStyle
    @Binding var position: CaptionPosition
    @Binding var tune: CaptionTune
    @Binding var framing: FramingMode
    let sourceURL: URL
    let clip: EDLClip
    let cues: [SRTCue]
    let words: [TimedToken]?
    let cropFocus: CGPoint?
    let cropZoom: CGFloat
    let hasWords: Bool
    let retranscribe: () -> Void
    let onDescribe: ((String) async throws -> LookDescribeDraft)?
    let dismiss: () -> Void

    private enum Pane: String, CaseIterable, Identifiable {
        case presets, tune, describe
        var id: String { rawValue }
        var title: String {
            switch self {
            case .presets: "预设"
            case .tune: "调节"
            case .describe: "描述"
            }
        }
    }

    @State private var pane: Pane = .presets
    @State private var prompt = ""
    @State private var describeError: String?
    @State private var describing = false

    var body: some View {
        ZStack {
            StudioTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                LookStudioLivePreview(
                    sourceURL: sourceURL, clip: clip, cues: cues, words: words,
                    style: style, position: position, tune: tune, framing: framing,
                    cropFocus: cropFocus, cropZoom: cropZoom
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .frame(maxHeight: framing == .sourceAspect ? 200 : 360)
                panePicker
                    .padding(.top, 16)
                ScrollView {
                    Group {
                        switch pane {
                        case .presets: presetPane
                        case .tune: tunePane
                        case .describe: describePane
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .padding(.bottom, 28)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Button("关闭", action: dismiss)
                .font(.body.weight(.medium))
                .foregroundStyle(StudioTheme.muted)
            Spacer()
            Text(ExportLookText.framingTitle(framing))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 44, height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var panePicker: some View {
        HStack(spacing: 6) {
            ForEach(Pane.allCases) { item in
                let on = pane == item
                Button {
                    withAnimation(StudioTheme.motion) { pane = item }
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(on ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(on ? StudioTheme.accent : StudioTheme.raised, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    private var presetPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(LookPreset.allCases) { preset in
                StudioChoiceCard(
                    title: preset.title,
                    note: preset.note,
                    selected: matches(preset)
                ) {
                    apply(preset)
                }
            }
        }
    }

    private var tunePane: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(ExportLookText.framingNote(framing))
                .font(.caption)
                .foregroundStyle(StudioTheme.muted)
            StudioChipRow(values: FramingMode.allCases, selection: $framing) {
                ExportLookText.framingTitle($0)
            }
            .padding(.horizontal, -20)

            Text(ExportLookText.styleNote(style, hasWords: hasWords))
                .font(.caption)
                .foregroundStyle(StudioTheme.muted)
            StudioChipRow(values: CaptionStyle.allCases, selection: $style) {
                ExportLookText.styleTitle($0)
            }
            .padding(.horizontal, -20)

            if style == .highlightWord, !hasWords {
                Button("重新转写", action: retranscribe)
                    .buttonStyle(QuietButtonStyle())
            }

            VStack(alignment: .leading, spacing: 10) {
                Slider(value: bandYBinding, in: 0...1)
                Text("字幕带 \(Int(tune.bandY * 100))%")
                    .font(.caption)
                    .foregroundStyle(StudioTheme.muted)
                Slider(value: fontScaleBinding, in: 0.6...1.8)
                Text(String(format: "字号 ×%.1f", tune.fontScale))
                    .font(.caption)
                    .foregroundStyle(StudioTheme.muted)
                HStack(spacing: 10) {
                    ForEach(LookColorChip.textChoices, id: \.self) { hex in
                        LookColorChip.swatch(hex, selected: tune.textHex == hex) {
                            tune = CaptionTune(
                                bandY: tune.bandY, fontScale: tune.fontScale,
                                textHex: hex, accentHex: tune.accentHex
                            )
                        }
                    }
                }
                HStack(spacing: 10) {
                    ForEach(LookColorChip.accentChoices, id: \.self) { hex in
                        LookColorChip.swatch(hex, selected: tune.accentHex == hex) {
                            tune = CaptionTune(
                                bandY: tune.bandY, fontScale: tune.fontScale,
                                textHex: tune.textHex, accentHex: hex
                            )
                        }
                    }
                }
            }
            .disabled(!style.burnsCaptions)
            .opacity(style.burnsCaptions ? 1 : 0.35)
        }
    }

    private var describePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("竖屏跟人，大白字靠下", text: $prompt, axis: .vertical)
                .lineLimit(3...5)
                .padding(12)
                .background(StudioTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if let describeError {
                Text(describeError).font(.footnote).foregroundStyle(.orange)
            }
            Button {
                Task { await runDescribe() }
            } label: {
                if describing { ProgressView() } else { Text("套用").frame(maxWidth: .infinity) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || describing || onDescribe == nil)
        }
    }

    private func matches(_ preset: LookPreset) -> Bool {
        style == preset.style && framing == preset.framing && tune == preset.tune
    }

    private func apply(_ preset: LookPreset) {
        style = preset.style
        framing = preset.framing
        tune = preset.tune
        position = nearestPosition(for: preset.tune.bandY)
    }

    private func nearestPosition(for bandY: Double) -> CaptionPosition {
        if bandY < 0.35 { return .bottom }
        if bandY < 0.65 { return .middle }
        return .top
    }

    private var bandYBinding: Binding<Double> {
        Binding(
            get: { tune.bandY },
            set: {
                tune = CaptionTune(bandY: $0, fontScale: tune.fontScale, textHex: tune.textHex, accentHex: tune.accentHex)
                position = nearestPosition(for: $0)
            }
        )
    }

    private var fontScaleBinding: Binding<Double> {
        Binding(
            get: { tune.fontScale },
            set: {
                tune = CaptionTune(bandY: tune.bandY, fontScale: $0, textHex: tune.textHex, accentHex: tune.accentHex)
            }
        )
    }

    private func runDescribe() async {
        guard let onDescribe else { return }
        describing = true
        describeError = nil
        defer { describing = false }
        do {
            let draft = try await onDescribe(prompt)
            style = draft.style
            framing = draft.framing
            tune = draft.tune
            position = nearestPosition(for: draft.tune.bandY)
        } catch {
            describeError = ErrorText.describe(error)
        }
    }
}

/// Result of a language describe call (ADR-0027); applied atomically into AppSettings fields.
public struct LookDescribeDraft: Equatable, Sendable {
    public var style: CaptionStyle
    public var framing: FramingMode
    public var tune: CaptionTune

    public init(style: CaptionStyle, framing: FramingMode, tune: CaptionTune) {
        self.style = style
        self.framing = framing
        self.tune = tune
    }
}
