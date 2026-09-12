// Why: the presentational pieces of the results workbench — stage and clip table. The stage plays
// the selected clip straight from the source composition (no export) in the source's own aspect
// ratio; the only wait is the sub-second composition build, covered by the clip's real first frame.
// Posters are real frames; a failed grab stays dark rather than substituting a stock image.

import AVFoundation
import LiveSliceCore
import LiveSliceRender
import SwiftUI

/// What the stage has for the selected clip: nothing yet, a playable preview, or a build error.
enum PreviewState {
    case loading
    case ready(ClipPreview)
    case failed(String)
}

/// The player area: the live preview as soon as it exists, the clip's own first frame until then.
/// `aspect` is the source's width/height once known (all clips of one source share it).
struct ClipStage: View {
    let preview: PreviewState
    let aspect: CGFloat
    let sourceURL: URL
    let posterSeconds: Double
    let captionStyle: CaptionStyle
    let captionTune: CaptionTune
    let clipID: String
    var cropFocus: CGPoint? = nil
    var cropZoom: CGFloat = 1
    var showCropPad: Bool = false
    var onCropChange: ((CGPoint) -> Void)? = nil
    var onCropZoom: ((CGFloat) -> Void)? = nil
    var onCropReset: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color.black
            switch preview {
            case .ready(let preview):
                ClipPlayerView(preview: preview, style: captionStyle, tune: captionTune, clipID: clipID)
                    .transition(.opacity)
            case .loading:
                poster(dim: 0.45)
            case .failed(let message):
                poster(dim: 0.7)
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.caption.monospaced())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .lineLimit(6)
                }
                .padding(16)
            }
            if showCropPad {
                CropFocusPad(
                    focus: cropFocus, zoom: cropZoom,
                    onFocus: { onCropChange?($0) },
                    onZoom: { onCropZoom?($0) },
                    onReset: { onCropReset?() }
                )
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        .animation(StudioTheme.motion, value: stateKey)
    }

    private func poster(dim: Double) -> some View {
        ClipPoster(
            url: sourceURL, seconds: posterSeconds, maximumSize: CGSize(width: 1920, height: 1920), contentMode: .fit
        )
        .overlay(Color.black.opacity(dim))
    }

    private var stateKey: Int {
        switch preview {
        case .loading: 0
        case .ready: 1
        case .failed: 2
        }
    }
}

/// The table of contents: number, first frame, title, duration, export mark. Tapping a row plays
/// it on the stage; the ⋮ opens 依据 (hidden on iPad where the rationale is already on screen).
struct ClipTable: View {
    let sourceURL: URL
    let clips: [EDLClip]
    let selectedID: String
    let renders: [String: ClipRenderState]
    let select: (String) -> Void
    /// Tap on the selected row; nil where the rationale is already on screen (iPad), which also hides the ⓘ.
    let showRationale: (() -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                        row(index: index + 1, clip: clip)
                            .id(clip.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: selectedID) { _, id in
                withAnimation(StudioTheme.motion) { proxy.scrollTo(id, anchor: nil) }
            }
        }
    }

    private func row(index: Int, clip: EDLClip) -> some View {
        let isSelected = clip.id == selectedID
        return HStack(spacing: 4) {
            Button {
                if clip.id == selectedID {
                    showRationale?()
                } else {
                    withAnimation(StudioTheme.motion) { select(clip.id) }
                }
            } label: {
                rowLabel(index: index, clip: clip)
            }
            .buttonStyle(.plain)
            if let showRationale {
                Menu {
                    Button("依据") {
                        select(clip.id)
                        showRationale()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.medium))
                        .foregroundStyle(StudioTheme.muted)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("依据")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(isSelected ? StudioTheme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func rowLabel(index: Int, clip: EDLClip) -> some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", index))
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(StudioTheme.muted)
                .frame(width: 28, alignment: .leading)
            ClipPoster(url: sourceURL, seconds: clip.startSec, maximumSize: CGSize(width: 180, height: 120))
                .frame(width: 52, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(clip.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(TimeText.clock(clip.keptDurationSec))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(StudioTheme.muted)
                    exportMark(for: clip)
                }
            }
            Spacer(minLength: 6)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func exportMark(for clip: EDLClip) -> some View {
        switch renders[clip.id] {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(StudioTheme.success)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        case .rendering:
            ProgressView().controlSize(.mini).tint(.white)
        case .idle, .none:
            EmptyView()
        }
    }
}

/// One frame from the source at `seconds`. A grab failure leaves the poster dark.
struct ClipPoster: View {
    let url: URL
    let seconds: Double
    let maximumSize: CGSize
    /// `.fill` for strip cards; the stage uses `.fit` when the export keeps the whole frame.
    var contentMode: ContentMode = .fill
    @State private var image: CGImage?

    var body: some View {
        // Color.clear takes the proposed size; the image is overlaid and clipped so a `.fill`
        // poster never inflates its parent (which pushed strip labels out of the card).
        Color.clear
            .background(StudioTheme.raised)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .transition(.opacity)
                }
            }
            .clipped()
            .animation(.easeOut(duration: 0.25), value: image == nil)
        .task(id: "\(url.path)-\(seconds)-\(maximumSize.width)") {
            image = await Self.frame(url: url, at: seconds, maximumSize: maximumSize)
        }
    }

    private static func frame(url: URL, at seconds: Double, maximumSize: CGSize) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        do {
            return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        } catch {
            return nil
        }
    }
}

/// Durations and clock times as people read them, not as timecode.
enum TimeText {
    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) 秒" }
        return "\(total / 60) 分 \(total % 60) 秒"
    }

    /// Compact Chinese duration used on the workbench pills (`48秒`, `1分02秒`, `7分10秒`).
    static func compact(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        if h > 0 { return s == 0 ? "\(h)小时\(m)分" : String(format: "%d小时%d分%02d秒", h, m, s) }
        if m > 0 { return s == 0 ? "\(m)分" : String(format: "%d分%02d秒", m, s) }
        return "\(s)秒"
    }
}