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
}
