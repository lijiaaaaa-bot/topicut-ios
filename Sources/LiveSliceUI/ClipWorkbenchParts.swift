// Why: the presentational pieces of the results workbench — stage and posters. The stage plays
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
    /// Workbench only: long-press opens EDL edit. Look studio leaves this nil.
    var onHold: (() -> Void)? = nil
    @State private var holdArmed = false
    @State private var holdPulse = 0
    @State private var playback = PlaybackControl()

    var body: some View {
        ZStack {
            Color.black
            switch preview {
            case .ready(let preview):
                ClipPlayerView(
                    preview: preview, style: captionStyle, tune: captionTune, clipID: clipID,
                    playback: onHold == nil ? nil : playback
                )
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
            if onHold != nil, !showCropPad {
                HoldToTrimChrome(armed: holdArmed)
                HoldToTrimSensor(
                    onTap: { playback.toggle() },
                    onArmed: { holdArmed = true; holdPulse += 1 },
                    onComplete: { holdArmed = false; onHold?() },
                    onCancel: { holdArmed = false }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .accessibilityHidden(true)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        .animation(StudioTheme.motion, value: stateKey)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: holdPulse)
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