import CoreGraphics
import Testing
@testable import LiveSliceUI
import LiveSliceRender

/// ADR-0024: the option cards are drawn by the real rasterizer, and the words say what each one does.
struct ExportLookTextTests {
    @Test func everyStyleHasItsOwnTitleAndNote() {
        let titles = CaptionStyle.allCases.map(ExportLookText.styleTitle)
        #expect(Set(titles).count == titles.count)
        #expect(titles.allSatisfy { !$0.isEmpty })
        for hasWords in [true, false] {
            let notes = CaptionStyle.allCases.map { ExportLookText.styleNote($0, hasWords: hasWords) }
            #expect(Set(notes).count == notes.count)
        }
        #expect(ExportLookText.styleNote(.highlightWord, hasWords: true) != ExportLookText.styleNote(.highlightWord, hasWords: false))
    }

    @Test func saveTitleNamesEveryLookButTheDefault() {
        #expect(ExportLookText.saveTitle(style: .clean, position: .bottom) == "保存到相册")
        #expect(ExportLookText.saveTitle(style: .highlightWord, position: .bottom).contains(ExportLookText.styleTitle(.highlightWord)))
        #expect(ExportLookText.saveTitle(style: .none, position: .bottom).contains(ExportLookText.styleTitle(.none)))
        #expect(ExportLookText.saveTitle(style: .clean, position: .top).contains(ExportLookText.positionTitle(.top)))
        #expect(ExportLookText.saveTitle(style: .none, position: .top) == "保存到相册 · \(ExportLookText.styleTitle(.none))", "无字幕不烧录，位置不进按钮文案")
        #expect(ExportLookText.saveTitle(style: .clean, position: .bottom, framing: .phonePortrait).contains(ExportLookText.framingTitle(.phonePortrait)))
    }

    @Test func framingTitlesCoverEveryCase() {
        let titles = FramingMode.allCases.map(ExportLookText.framingTitle)
        #expect(Set(titles).count == titles.count)
        #expect(ExportLookText.framingNote(.phonePortrait).contains("人脸"))
    }

    @Test func positionTitlesCoverEveryCase() {
        let titles = CaptionPosition.allCases.map(ExportLookText.positionTitle)
        #expect(Set(titles).count == titles.count)
    }

    @Test @MainActor func samplesAreDrawnForCaptionStylesAndNotForNone() throws {
        let clean = try #require(try CaptionSample.render(style: .clean, width: 480, height: 270))
        let words = try #require(try CaptionSample.render(style: .highlightWord, width: 480, height: 270))
        #expect(clean.width == 480 && clean.height == 270)
        #expect(try CaptionSample.render(style: .none, width: 480, height: 270) == nil)
        #expect(try CaptionSample.render(style: .clean, width: 0, height: 270) == nil)
        #expect(accentPixels(in: clean) == 0)
        #expect(accentPixels(in: words) > 50, "the highlight sample shows the accent word")
    }

    /// Pixels close to SubtitleStyle's accent colour.
    private func accentPixels(in image: CGImage) -> Int {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
        let bpr = image.bytesPerRow
        var count = 0
        for y in 0..<image.height {
            for x in 0..<image.width {
                let p = y * bpr + x * 4
                let r = Int(bytes[p]), g = Int(bytes[p + 1]), b = Int(bytes[p + 2])
                if r > 200, g > 150, g < 230, b < 90 { count += 1 }
            }
        }
        return count
    }
}
