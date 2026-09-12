// Why: every caption image — plain, backdrop, or a single accent word — must come from one Core Text
// layout, or the accent crop lands beside the word instead of on it. This type owns that layout
// (frame, line origins, vertical centring) and the drawing passes over it; the rasterizer only
// decides which passes to run.

import CoreGraphics
import CoreText
import Foundation

struct Layout {
    let text: String
    let band: CGRect
    let style: SubtitleStyle
    let font: CTFont
    let frame: CTFrame
    let lines: [CTLine]
    let origins: [CGPoint]
    /// Shift that moves the top-aligned frame so its lines sit in the middle of the band.
    let verticalOffset: CGFloat

    init(text: String, width: Int, height: Int, style: SubtitleStyle) throws {
        guard width > 0, height > 0 else { throw SubtitleRasterizerError.contextUnavailable }
        self.text = text
        self.style = style
        band = CGRect(x: 0, y: 0, width: width, height: height)
        font = CTFontCreateUIFontForLanguage(.emphasizedSystem, style.fontSize, nil)
            ?? CTFontCreateWithName("PingFangSC-Semibold" as CFString, style.fontSize, nil)
        // The frame always spans the whole band: CTFramesetterSuggestFrameSizeWithConstraints
        // under-reports the line height when glyphs come from a fallback (CJK) font, and a frame
        // shorter than its first line draws nothing at all.
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): Self.centred(),
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributed.length), CGPath(rect: band, transform: nil), nil)
        guard let lines = CTFrameGetLines(frame) as? [CTLine] else { throw SubtitleRasterizerError.contextUnavailable }
        self.lines = lines
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        self.origins = origins
        verticalOffset = Self.centringOffset(lines: lines, origins: origins, bandHeight: CGFloat(height))
    }

    func makeContext() throws -> CGContext {
        guard let context = CGContext(
            data: nil, width: Int(band.width), height: Int(band.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw SubtitleRasterizerError.contextUnavailable }
        context.clear(band)
        return context
    }

    /// Stroke pass then fill pass, so the outline never eats into the glyph body. With `only`, every
    /// character outside the range is drawn transparent: same layout, one word visible.
    func draw(in context: CGContext, fill: CGColor, stroke: CGColor, strokeWidth: CGFloat, only: Range<Int>? = nil) {
        context.saveGState()
        context.translateBy(x: 0, y: verticalOffset)
        for pass in [strokeAttributes(stroke, width: strokeWidth), fillAttributes(fill)] {
            let attributed = NSMutableAttributedString(string: text, attributes: pass)
            if let only {
                let hidden = [NSAttributedString.Key(kCTForegroundColorAttributeName as String): SubtitleRasterizer.clear,
                              NSAttributedString.Key(kCTStrokeColorAttributeName as String): SubtitleRasterizer.clear]
                if only.lowerBound > 0 { attributed.addAttributes(hidden, range: NSRange(location: 0, length: only.lowerBound)) }
                let tail = text.utf16.count - only.upperBound
                if tail > 0 { attributed.addAttributes(hidden, range: NSRange(location: only.upperBound, length: tail)) }
            }
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let pass = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributed.length), CGPath(rect: band, transform: nil), nil)
            CTFrameDraw(pass, context)
        }
        context.restoreGState()
    }

    /// One rounded dark block per line, hugging the line's typographic bounds.
    func drawBackdrop(in context: CGContext) {
        let padX = style.fontSize * 0.28, padY = style.fontSize * 0.10
        context.setFillColor(SubtitleRasterizer.backdropColor)
        for (line, origin) in zip(lines, origins) {
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
            let rect = CGRect(x: origin.x - padX, y: origin.y - descent - padY + verticalOffset, width: width + 2 * padX, height: ascent + descent + 2 * padY)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: style.fontSize * 0.22, cornerHeight: style.fontSize * 0.22, transform: nil))
        }
        context.fillPath()
    }

    /// Band rectangle covered by the glyphs of `range` (UTF-16 offsets), across every line it touches.
    func rect(of range: Range<Int>) -> CGRect {
        var union = CGRect.null
        for (line, origin) in zip(lines, origins) {
            let lineRange = CTLineGetStringRange(line)
            let lo = max(range.lowerBound, Int(lineRange.location)), hi = min(range.upperBound, Int(lineRange.location + lineRange.length))
            guard hi > lo else { continue }
            var ascent: CGFloat = 0, descent: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            let x0 = CTLineGetOffsetForStringIndex(line, lo, nil), x1 = CTLineGetOffsetForStringIndex(line, hi, nil)
            union = union.union(CGRect(x: origin.x + min(x0, x1), y: origin.y - descent + verticalOffset, width: abs(x1 - x0), height: ascent + descent))
        }
        return union
    }

    private func fillAttributes(_ color: CGColor) -> [NSAttributedString.Key: Any] {
        [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): Self.centred(),
        ]
    }

    private func strokeAttributes(_ color: CGColor, width: CGFloat) -> [NSAttributedString.Key: Any] {
        [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTStrokeColorAttributeName as String): color,
            NSAttributedString.Key(kCTStrokeWidthAttributeName as String): abs(width) * 2,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): Self.centred(),
        ]
    }

    private static func centred() -> CTParagraphStyle {
        var alignment = CTTextAlignment.center
        let setting = withUnsafeMutablePointer(to: &alignment) { pointer in
            CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer)
        }
        return CTParagraphStyleCreate([setting], 1)
    }

    private static func centringOffset(lines: [CTLine], origins: [CGPoint], bandHeight: CGFloat) -> CGFloat {
        guard let first = lines.first, let last = lines.last, let firstOrigin = origins.first, let lastOrigin = origins.last else { return 0 }
        var ascent: CGFloat = 0, descent: CGFloat = 0
        CTLineGetTypographicBounds(first, &ascent, nil, nil)
        CTLineGetTypographicBounds(last, nil, &descent, nil)
        let top = firstOrigin.y + ascent
        let bottom = lastOrigin.y - descent
        return (bandHeight + (top - bottom)) / 2 - top
    }
}
