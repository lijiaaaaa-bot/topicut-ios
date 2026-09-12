import CoreGraphics
import Testing
@testable import LiveSliceRender

struct SubtitleRasterizerTests {
    private func opaquePixelCount(_ image: CGImage) -> Int {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return -1 }
        var count = 0
        let bytesPerRow = image.bytesPerRow
        for y in 0..<image.height {
            for x in 0..<image.width where bytes[y * bytesPerRow + x * 4 + 3] > 128 { count += 1 }
        }
        return count
    }

    @Test func drawsChineseGlyphsOnTransparentBackground() throws {
        let style = SubtitleStyle.vertical1080p
        let image = try SubtitleRasterizer.image(text: "字幕烧录测试", width: 952, height: Int(style.bandHeight), style: style)
        #expect(image.width == 952)
        #expect(image.height == Int(style.bandHeight))
        let opaque = opaquePixelCount(image)
        #expect(opaque > 2_000, "glyphs must cover a visible area, got \(opaque) px")
        #expect(opaque < 952 * Int(style.bandHeight) / 2, "most of the band must stay transparent")
    }

    @Test func longerTextCoversMorePixels() throws {
        let style = SubtitleStyle.vertical1080p
        let short = try SubtitleRasterizer.image(text: "短", width: 952, height: Int(style.bandHeight), style: style)
        let long = try SubtitleRasterizer.image(text: "这是一句明显更长的字幕文本用于测试", width: 952, height: Int(style.bandHeight), style: style)
        #expect(opaquePixelCount(long) > opaquePixelCount(short) * 3)
    }

    @Test func zeroSizeIsAnError() {
        #expect(throws: SubtitleRasterizerError.contextUnavailable) {
            try SubtitleRasterizer.image(text: "x", width: 0, height: 10, style: .vertical1080p)
        }
    }

    private func accentPixelCount(_ image: CGImage) -> Int {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return -1 }
        var count = 0
        for y in 0..<image.height {
            for x in 0..<image.width {
                let p = y * image.bytesPerRow + x * 4
                if bytes[p + 3] > 128, bytes[p] > 180, bytes[p + 1] > 150, bytes[p + 2] < 90 { count += 1 }
            }
        }
        return count
    }

    // ADR-0023
    @Test func backdropLookCoversMoreOfTheBandThanClean() throws {
        let style = SubtitleStyle.vertical1080p
        let clean = try SubtitleRasterizer.image(text: "先找话题 再动剪刀", width: 952, height: Int(style.bandHeight), style: style, look: .clean)
        let backdrop = try SubtitleRasterizer.image(text: "先找话题 再动剪刀", width: 952, height: Int(style.bandHeight), style: style, look: .backdrop)
        #expect(opaquePixelCount(backdrop) > opaquePixelCount(clean) * 3 / 2, "the rounded block behind the line must be visible")
        #expect(accentPixelCount(backdrop) == 0)
    }

    @Test func wordImageIsAccentOnlyAndSitsOverTheWord() throws {
        let style = SubtitleStyle.vertical1080p
        let text = "先找话题 再动剪刀"
        let (first, firstFrame) = try SubtitleRasterizer.wordImage(text: text, range: 0..<4, width: 952, height: Int(style.bandHeight), style: style)
        let (second, secondFrame) = try SubtitleRasterizer.wordImage(text: text, range: 5..<9, width: 952, height: Int(style.bandHeight), style: style)
        #expect(accentPixelCount(first) > 500)
        #expect(first.width < 952 / 2, "cropped to the word, not the band")
        #expect(firstFrame.minX < secondFrame.minX, "second word is to the right of the first")
        #expect(firstFrame.maxX <= secondFrame.minX + 4)
        #expect(abs(firstFrame.midY - secondFrame.midY) < 2, "same line")
        #expect(Int(firstFrame.width) == first.width && Int(firstFrame.height) == first.height)
        // Centre of the band vertically: the same centring the plain image uses.
        #expect(abs(firstFrame.midY - style.bandHeight / 2) < style.fontSize)
        #expect(accentPixelCount(second) > 500)
    }

    @Test func wordRangeOutsideTextIsAnError() {
        #expect(throws: SubtitleRasterizerError.wordRangeOutOfText(3..<3)) {
            try SubtitleRasterizer.wordImage(text: "短句", range: 3..<3, width: 400, height: 100, style: .vertical1080p)
        }
        #expect(throws: SubtitleRasterizerError.wordRangeOutOfText(0..<9)) {
            try SubtitleRasterizer.wordImage(text: "短句", range: 0..<9, width: 400, height: 100, style: .vertical1080p)
        }
    }
}
