import CoreGraphics
import Testing
@testable import LiveSliceRender

struct CaptionLayoutTests {
    @Test func wordRectsFollowReadingOrderOnOneLine() throws {
        let style = SubtitleStyle.vertical1080p
        let layout = try Layout(text: "先找话题 再动剪刀", width: 952, height: Int(style.bandHeight), style: style)
        #expect(layout.lines.count == 1)
        let first = layout.rect(of: 0..<4), second = layout.rect(of: 5..<9)
        #expect(first.width > style.fontSize * 3, "four CJK glyphs are at least three em wide")
        #expect(first.maxX <= second.minX + 1)
        #expect(abs(first.midY - second.midY) < 0.5)
        #expect(layout.rect(of: 0..<9).width > first.width + second.width)
    }

    @Test func wrappedTextPutsLaterWordsOnALowerLine() throws {
        let style = SubtitleStyle.vertical1080p
        let text = "这是一句明显更长的字幕文本用来验证换行后的位置"
        let layout = try Layout(text: text, width: 952, height: Int(style.bandHeight), style: style)
        #expect(layout.lines.count == 2)
        let head = layout.rect(of: 0..<2), tail = layout.rect(of: (text.utf16.count - 2)..<text.utf16.count)
        #expect(head.minY > tail.minY, "the second line sits below the first in the y-up band")
        #expect(layout.rect(of: 100..<120).isNull, "a range past the text covers nothing")
    }

    @Test func zeroSizeIsAnError() {
        #expect(throws: SubtitleRasterizerError.contextUnavailable) {
            try Layout(text: "x", width: 0, height: 10, style: .vertical1080p)
        }
    }
}
