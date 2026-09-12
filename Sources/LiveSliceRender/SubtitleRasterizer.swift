// Why: CATextLayer does not reliably draw text inside AVAssetExportSession's offscreen Core
// Animation renderer (verified: empty layer bounds, no glyphs). Rasterizing captions with Core
// Text into a CGImage is deterministic on iOS and macOS and can be pixel-tested without an export.
// The word-highlight look (ADR-0023) reuses the same layout: a backdrop image per caption, plus one
// small accent image per word cropped out of an identical layout so glyphs line up exactly.

import CoreGraphics
import CoreText
import Foundation

public enum SubtitleRasterizerError: Error, Equatable, Sendable, LocalizedError {
    case contextUnavailable
    case imageUnavailable
    /// The word range points outside the text or at no glyph (e.g. an empty range).
    case wordRangeOutOfText(Range<Int>)

    public var errorDescription: String? {
        switch self {
        case .contextUnavailable: "无法创建字幕画布"
        case .imageUnavailable: "无法生成字幕图像"
        case .wordRangeOutOfText(let range): "高亮词范围越界（\(range.lowerBound)…\(range.upperBound)）"
        }
    }
}

/// Which colours a caption image uses; geometry comes from SubtitleStyle.
public enum CaptionLook: Equatable, Sendable {
    /// White fill, black stroke, transparent background (the 1.0 look).
    case clean
    /// Dark rounded backdrop behind each line, white fill, thinner stroke.
    case backdrop
}

public enum SubtitleRasterizer {
    static let accent = CGColor(red: 1, green: 0.84, blue: 0.04, alpha: 1)
    static let backdropColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.58)

    /// Draws `text` (centred, wrapped to `width`) onto a transparent image. `height` is the caption
    /// band height in pixels; overflow is clipped, never resized silently.
    public static func image(
        text: String, width: Int, height: Int, style: SubtitleStyle, look: CaptionLook = .clean,
        fill: CGColor? = nil, accent: CGColor? = nil
    ) throws -> CGImage {
        let layout = try Layout(text: text, width: width, height: height, style: style)
        let context = try layout.makeContext()
        if look == .backdrop { layout.drawBackdrop(in: context) }
        let fillColor = fill ?? white
        layout.draw(
            in: context, fill: fillColor, stroke: black,
            strokeWidth: look == .clean ? style.strokeWidth : style.strokeWidth / 2
        )
        guard let image = context.makeImage() else { throw SubtitleRasterizerError.imageUnavailable }
        return image
    }

    /// The word at `range` (UTF-16 offsets into `text`) in the accent colour, cropped to its glyphs,
    /// and the rectangle it occupies in the band (origin bottom-left, band coordinates) — the same
    /// layout as `image`, so the crop sits exactly over the plain word.
    public static func wordImage(
        text: String, range: Range<Int>, width: Int, height: Int, style: SubtitleStyle,
        accent: CGColor? = nil
    ) throws -> (image: CGImage, frame: CGRect) {
        guard !range.isEmpty, range.upperBound <= text.utf16.count else { throw SubtitleRasterizerError.wordRangeOutOfText(range) }
        let layout = try Layout(text: text, width: width, height: height, style: style)
        let context = try layout.makeContext()
        layout.draw(
            in: context, fill: accent ?? Self.accent, stroke: black, strokeWidth: style.strokeWidth / 2, only: range
        )
        guard let full = context.makeImage() else { throw SubtitleRasterizerError.imageUnavailable }
        let frame = layout.rect(of: range).insetBy(dx: -abs(style.strokeWidth) - 2, dy: -abs(style.strokeWidth) - 2)
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !frame.isEmpty else { throw SubtitleRasterizerError.wordRangeOutOfText(range) }
        // CGImage.cropping works in image pixels with the origin at the top-left; the band is y-up.
        let crop = CGRect(x: frame.minX, y: CGFloat(height) - frame.maxY, width: frame.width, height: frame.height).integral
        guard let image = full.cropping(to: crop) else { throw SubtitleRasterizerError.imageUnavailable }
        return (image, crop.flippedBack(bandHeight: CGFloat(height)))
    }

    static let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    static let clear = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
}

private extension CGRect {
    /// Back from top-left image coordinates to the y-up band coordinates the layer tree uses.
    func flippedBack(bandHeight: CGFloat) -> CGRect {
        CGRect(x: minX, y: bandHeight - maxY, width: width, height: height)
    }
}
