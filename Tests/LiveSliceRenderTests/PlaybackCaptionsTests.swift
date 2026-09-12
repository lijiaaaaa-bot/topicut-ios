import CoreGraphics
import Testing
import LiveSliceCore
@testable import LiveSliceRender

struct PlaybackCaptionsTests {
    @Test func makeBuildsPlainWordsOrNoneAndRejectsHighlightWithoutTimings() throws {
        let clip = try EDLClip(
            id: "c1", title: "t", reason: "r", score: 0.5, tags: [], category: nil,
            frameworkId: "f", frameworkTitle: "f", mode: EDLClip.modeContinuous,
            segments: [EDLSegment(startSec: 0, endSec: 2, reason: nil)], removedSegments: []
        )
        let timeline = try ClipTimeline(clip: clip)
        let cues = [SRTCue(index: 1, start: 0, end: 2, text: "先找")]
        let words = [TimedToken(text: "先找", start: 0, end: 2)]
        #expect(try PlaybackCaptions.make(style: .none, timeline: timeline, cues: cues, words: words, clipID: "c1") == .none)
        guard case .plain(let windows) = try PlaybackCaptions.make(style: .clean, timeline: timeline, cues: cues, words: nil, clipID: "c1") else {
            Issue.record("expected plain"); return
        }
        #expect(windows.count == 1)
        #expect(throws: ClipRendererError.wordTimingsUnavailable(clipID: "c1")) {
            _ = try PlaybackCaptions.make(style: .highlightWord, timeline: timeline, cues: cues, words: nil, clipID: "c1")
        }
        guard case .words(let captions) = try PlaybackCaptions.make(style: .highlightWord, timeline: timeline, cues: cues, words: words, clipID: "c1") else {
            Issue.record("expected words"); return
        }
        #expect(captions.count == 1)
    }

    @Test func noneStyleDrawsNothingAndCleanDrawsABand() throws {
        let windows = [SubtitleWindow(text: "试看叠字", start: 0, end: 2)]
        #expect(try PreviewCaptionPainter.image(captions: .none, at: 1, width: 400, height: 80, style: .vertical1080p) == nil)
        let clean = try #require(try PreviewCaptionPainter.image(
            captions: .plain(windows), at: 1, width: 400, height: 80, style: .vertical1080p
        ))
        #expect(clean.width == 400)
        #expect(try PreviewCaptionPainter.image(captions: .plain(windows), at: 3, width: 400, height: 80, style: .vertical1080p) == nil)
    }

    @Test func bandInViewScalesInsetsWithTheView() {
        let render = CGSize(width: 1080, height: 1920)
        let view = CGSize(width: 270, height: 480)
        let layout = PreviewCaptionPainter.bandInView(position: .bottom, renderSize: render, viewSize: view)
        #expect(abs(layout.bottomInset - SubtitleStyle.vertical1080p.bottomInset / 4) < 0.5)
        #expect(abs(layout.bandSize.height - SubtitleStyle.vertical1080p.bandHeight / 4) < 0.5)
        #expect(abs(layout.style.fontSize - SubtitleStyle.vertical1080p.fontSize / 4) < 0.5)
    }

    /// Build 23: phone-sized player + full render font made word crops empty → wordRangeOutOfText on stage.
    @Test func highlightWordFrameFitsAPhoneSizedPlayer() throws {
        let caption = WordCaption(
            text: "战争爆发与庄园的黄昏来临之前", start: 0, end: 3,
            words: [
                WordWindow(range: 0..<4, start: 0, end: 1),
                WordWindow(range: 4..<10, start: 1, end: 2),
                WordWindow(range: 10..<14, start: 2, end: 3),
            ]
        )
        let frame = try #require(try PreviewCaptionPainter.frame(
            captions: .words([caption]), at: 1.2, position: .bottom,
            renderSize: CGSize(width: 1920, height: 1080), viewSize: CGSize(width: 350, height: 197), scale: 3
        ))
        #expect(frame.image.width > 0)
        #expect(frame.bandSize.height > 8)
        #expect(frame.bandSize.height < 80)
    }

    @Test func highlightWordKeepsBackdropWhenOneWordRangeIsOutOfText() throws {
        let caption = WordCaption(
            text: "先找", start: 0, end: 2,
            words: [WordWindow(range: 0..<99, start: 0, end: 2)]
        )
        let style = SubtitleStyle(fontSize: 40, bottomInset: 20, horizontalInset: 10, strokeWidth: -3)
        let image = try #require(try PreviewCaptionPainter.image(
            captions: .words([caption]), at: 0.5, width: 400, height: 100, style: style
        ))
        #expect(image.width == 400)
        #expect(image.height == 100)
    }

    @Test func highlightWordBandShowsAccentPixelsWhileTheWordIsSpoken() throws {
        let caption = WordCaption(
            text: "先找话题", start: 0, end: 2,
            words: [WordWindow(range: 0..<2, start: 0, end: 1), WordWindow(range: 2..<4, start: 1, end: 2)]
        )
        let style = SubtitleStyle(fontSize: 40, bottomInset: 20, horizontalInset: 10, strokeWidth: -3)
        let early = try #require(try PreviewCaptionPainter.image(captions: .words([caption]), at: 0.3, width: 400, height: 100, style: style))
        let late = try #require(try PreviewCaptionPainter.image(captions: .words([caption]), at: 1.3, width: 400, height: 100, style: style))
        #expect(accentPixels(in: early) > 20)
        #expect(accentPixels(in: late) > 20)
        #expect(early.dataProvider.flatMap { CFDataGetBytePtr($0.data) } != nil)
        #expect(CFEqual(early.dataProvider!.data, late.dataProvider!.data) == false)
    }

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
