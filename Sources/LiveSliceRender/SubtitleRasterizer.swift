// Why: CATextLayer does not reliably draw text inside AVAssetExportSession's offscreen Core
// Animation renderer (verified: empty layer bounds, no glyphs). Rasterizing captions with Core
// Text into a CGImage is deterministic on iOS and macOS and can be pixel-tested without an export.

import CoreGraphics
import CoreText
import Foundation

public enum SubtitleRasterizerError: Error, Equatable, Sendable {
    case contextUnavailable
    case imageUnavailable
}

public enum SubtitleRasterizer {
    /// Draws `text` (white, black stroke, centred, wrapped to `width`) onto a transparent image.
    /// `height` is the caption band height in pixels; overflow is clipped, never resized silently.
    public static func image(text: String, width: Int, height: Int, style: SubtitleStyle) throws -> CGImage {
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw SubtitleRasterizerError.contextUnavailable }
        let band = CGRect(x: 0, y: 0, width: width, height: height)
        context.clear(band)
        // Stroke first, then fill on top, so the outline never eats into the glyph body.
        // The frame always spans the whole band: CTFramesetterSuggestFrameSizeWithConstraints
        // under-reports the line height when glyphs come from a fallback (CJK) font, and a frame
        // shorter than its first line draws nothing at all.
        let passes = [strokeAttributes(style), fillAttributes(style)].map { attributes in
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            return CTFramesetterCreateFrame(
                framesetter, CFRange(location: 0, length: attributed.length), CGPath(rect: band, transform: nil), nil
            )
        }
        context.translateBy(x: 0, y: verticalCentringOffset(of: passes[1], bandHeight: CGFloat(height)))
        for pass in passes { CTFrameDraw(pass, context) }
        guard let image = context.makeImage() else { throw SubtitleRasterizerError.imageUnavailable }
        return image
    }

    /// How far to shift a top-aligned frame so its drawn lines sit in the middle of the band.
    private static func verticalCentringOffset(of frame: CTFrame, bandHeight: CGFloat) -> CGFloat {
        guard let lines = CTFrameGetLines(frame) as? [CTLine], let first = lines.first, let last = lines.last else { return 0 }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        CTLineGetTypographicBounds(first, &ascent, nil, nil)
        CTLineGetTypographicBounds(last, nil, &descent, nil)
        guard let firstOrigin = origins.first, let lastOrigin = origins.last else { return 0 }
        let top = firstOrigin.y + ascent
        let bottom = lastOrigin.y - descent
        let desiredTop = (bandHeight + (top - bottom)) / 2
        return desiredTop - top
    }

    private static func font(_ style: SubtitleStyle) -> CTFont {
        CTFontCreateUIFontForLanguage(.emphasizedSystem, style.fontSize, nil)
            ?? CTFontCreateWithName("PingFangSC-Semibold" as CFString, style.fontSize, nil)
    }

    private static func paragraph() -> CTParagraphStyle {
        var alignment = CTTextAlignment.center
        let setting = withUnsafeMutablePointer(to: &alignment) { pointer in
            CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer)
        }
        return CTParagraphStyleCreate([setting], 1)
    }

    private static func fillAttributes(_ style: SubtitleStyle) -> [NSAttributedString.Key: Any] {
        [
            NSAttributedString.Key(kCTFontAttributeName as String): font(style),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph(),
        ]
    }

    private static func strokeAttributes(_ style: SubtitleStyle) -> [NSAttributedString.Key: Any] {
        [
            NSAttributedString.Key(kCTFontAttributeName as String): font(style),
            NSAttributedString.Key(kCTStrokeColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            NSAttributedString.Key(kCTStrokeWidthAttributeName as String): abs(style.strokeWidth) * 2,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph(),
        ]
    }
}
