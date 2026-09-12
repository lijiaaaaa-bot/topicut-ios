// Why: ADR-0027/0030 — 成片 look is preset cards + framing chips first. Dense knobs and NL
// describe sit under 高级. Phone-portrait crop lives on this preview, not the workbench.

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
    var onCropFocus: ((CGPoint) -> Void)? = nil
    var onCropZoom: ((CGFloat) -> Void)? = nil
    var onCropReset: (() -> Void)? = nil
    let hasWords: Bool
    let retranscribe: () -> Void
    let onDescribe: ((String) async throws -> LookDescribeDraft)?
    let dismiss: () -> Void

    @State private var showAdvanced = false
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
                    cropFocus: cropFocus, cropZoom: cropZoom,
                    onCropFocus: onCropFocus, onCropZoom: onCropZoom, onCropReset: onCropReset
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .frame(maxHeight: framing == .sourceAspect ? 200 : 360)
                ScrollView {
                    primaryPane
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

    private var primaryPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            StudioChipRow(values: FramingMode.allCases, selection: $framing) {
                ExportLookText.framingTitle($0)
            }
            .padding(.horizontal, -20)
            ForEach(LookPreset.allCases) { preset in
                StudioChoiceCard(
                    title: preset.title,
                    note: preset.note,
                    selected: matches(preset)
                ) {
                    apply(preset)
                }
            }
            DisclosureGroup(isExpanded: $showAdvanced) {
                LookTunePane(
                    style: $style, tune: $tune, framing: framing,
                    hasWords: hasWords, retranscribe: retranscribe,
                    bandY: bandYBinding, fontScale: fontScaleBinding
                )
                .padding(.top, 12)
                LookDescribePane(
                    prompt: $prompt, describeError: describeError, describing: describing,
                    canSubmit: !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && !describing && onDescribe != nil,
                    submit: { Task { await runDescribe() } }
                )
                .padding(.top, 16)
            } label: {
                Text("高级")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(StudioTheme.muted)
            }
            .tint(StudioTheme.accent)
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
