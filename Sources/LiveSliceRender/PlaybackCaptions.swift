// Why: the workbench preview cannot burn captions into the player (export-only Core Animation
// tool). It still needs a live overlay so the user sees the current look and position while
// scrubbing a clip — the same CaptionStyle / CaptionPosition the export options sheet sets.
// Burning into the MP4 is a separate decision (`.none` skips burn); this type only describes what
// to draw at one composition instant.

import CoreGraphics
import Foundation
import LiveSliceCore

/// Captions keyed to composition time for the live overlay (and the same windows the export burns).
public enum PlaybackCaptions: Equatable, Sendable {
    case none
    case plain([SubtitleWindow])
    case words([WordCaption])

    /// Builds the captions for `style`. `.highlightWord` without word timings is a typed error —
    /// never a silent fall-back to plain captions (ADR-0024).
    public static func make(
        style: CaptionStyle, timeline: ClipTimeline, cues: [SRTCue], words: [TimedToken]?, clipID: String
    ) throws -> PlaybackCaptions {
        switch style {
        case .none: return .none
        case .clean: return .plain(timeline.subtitleWindows(for: cues))
        case .highlightWord:
            guard let words else { throw ClipRendererError.wordTimingsUnavailable(clipID: clipID) }
            return .words(try timeline.wordCaptions(for: cues, words: words))
        }
    }
}

/// One rasterized caption band for a composition instant, plus where it sits in the view.
public struct PreviewCaptionFrame: Equatable, Sendable {
    public let image: CGImage
    /// Distance from the bottom of the video view to the bottom of the band.
    public let bottomInset: CGFloat
    public let horizontalInset: CGFloat
    public let bandSize: CGSize
}

public enum PreviewCaptionPainter {
    /// Maps the export caption band into the video view. Font and stroke are scaled to the view so
    /// glyphs fit the band — using the full render font on a phone-sized band overflows and makes
    /// `wordImage` report `wordRangeOutOfText` for an empty crop (Build 23).
    public static func bandInView(
        tune: CaptionTune, renderSize: CGSize, viewSize: CGSize
    ) -> (style: SubtitleStyle, bottomInset: CGFloat, horizontalInset: CGFloat, bandSize: CGSize) {
        let export = tune.style(renderSize: renderSize)
        let sx = viewSize.width / max(renderSize.width, 1)
        let sy = viewSize.height / max(renderSize.height, 1)
        let style = SubtitleStyle(
            fontSize: export.fontSize * sy,
            bottomInset: export.bottomInset * sy,
            horizontalInset: export.horizontalInset * sx,
            strokeWidth: export.strokeWidth * sy
        )
        return (
            style: style,
            bottomInset: style.bottomInset,
            horizontalInset: style.horizontalInset,
            bandSize: CGSize(width: viewSize.width - 2 * style.horizontalInset, height: style.bandHeight)
        )
    }

    public static func bandInView(
        position: CaptionPosition, renderSize: CGSize, viewSize: CGSize
    ) -> (style: SubtitleStyle, bottomInset: CGFloat, horizontalInset: CGFloat, bandSize: CGSize) {
        bandInView(tune: .from(position: position), renderSize: renderSize, viewSize: viewSize)
    }

    /// Rasterizes the caption visible at `seconds`, or nil between cues / when style is `.none`.
    /// Draws at `scale`× the (already view-sized) band so the overlay stays sharp on retina.
    public static func frame(
        captions: PlaybackCaptions, at seconds: Double, tune: CaptionTune,
        renderSize: CGSize, viewSize: CGSize, scale: CGFloat = 3
    ) throws -> PreviewCaptionFrame? {
        guard viewSize.width > 1, viewSize.height > 1 else { return nil }
        let layout = bandInView(tune: tune, renderSize: renderSize, viewSize: viewSize)
        let pixelWidth = max(1, Int((layout.bandSize.width * scale).rounded()))
        let pixelHeight = max(1, Int((layout.bandSize.height * scale).rounded()))
        let drawStyle = SubtitleStyle(
            fontSize: layout.style.fontSize * scale,
            bottomInset: layout.style.bottomInset * scale,
            horizontalInset: layout.style.horizontalInset * scale,
            strokeWidth: layout.style.strokeWidth * scale
        )
        let fill = try tune.textCGColor()
        let accent = try tune.accentCGColor()
        guard let image = try image(
            captions: captions, at: seconds, width: pixelWidth, height: pixelHeight, style: drawStyle,
            fill: fill, accent: accent
        ) else { return nil }
        return PreviewCaptionFrame(
            image: image, bottomInset: layout.bottomInset, horizontalInset: layout.horizontalInset, bandSize: layout.bandSize
        )
    }

    public static func frame(
        captions: PlaybackCaptions, at seconds: Double, position: CaptionPosition,
        renderSize: CGSize, viewSize: CGSize, scale: CGFloat = 3
    ) throws -> PreviewCaptionFrame? {
        try frame(
            captions: captions, at: seconds, tune: .from(position: position),
            renderSize: renderSize, viewSize: viewSize, scale: scale
        )
    }

    public static func image(
        captions: PlaybackCaptions, at seconds: Double, width: Int, height: Int, style: SubtitleStyle,
        fill: CGColor? = nil, accent: CGColor? = nil
    ) throws -> CGImage? {
        switch captions {
        case .none:
            return nil
        case .plain(let windows):
            guard let window = windows.first(where: { seconds >= $0.start && seconds < $0.end }) else { return nil }
            return try SubtitleRasterizer.image(
                text: window.text, width: width, height: height, style: style, look: .clean, fill: fill
            )
        case .words(let captions):
            guard let caption = captions.first(where: { seconds >= $0.start && seconds < $0.end }) else { return nil }
            return try wordBand(
                caption: caption, at: seconds, width: width, height: height, style: style, fill: fill, accent: accent
            )
        }
    }

    private static func wordBand(
        caption: WordCaption, at seconds: Double, width: Int, height: Int, style: SubtitleStyle,
        fill: CGColor?, accent: CGColor?
    ) throws -> CGImage {
        let backdrop = try SubtitleRasterizer.image(
            text: caption.text, width: width, height: height, style: style, look: .backdrop, fill: fill
        )
        guard let word = caption.words.last(where: { seconds >= $0.start && seconds < $0.end }) else { return backdrop }
        let overlay: (image: CGImage, frame: CGRect)
        do {
            overlay = try SubtitleRasterizer.wordImage(
                text: caption.text, range: word.range, width: width, height: height, style: style, accent: accent
            )
        } catch let error as SubtitleRasterizerError {
            if case .wordRangeOutOfText = error { return backdrop }
            throw error
        }
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw SubtitleRasterizerError.contextUnavailable }
        context.draw(backdrop, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(overlay.image, in: overlay.frame)
        guard let image = context.makeImage() else { throw SubtitleRasterizerError.imageUnavailable }
        return image
    }
}
