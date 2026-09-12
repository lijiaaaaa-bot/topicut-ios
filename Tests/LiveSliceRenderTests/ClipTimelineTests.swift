import Testing
@testable import LiveSliceRender
import LiveSliceCore

struct ClipTimelineTests {
    private func clip(_ ranges: [(Double, Double)]) throws -> EDLClip {
        try EDLClip(
            id: "c1", title: "t", reason: "r", score: 0.5, tags: [], category: nil, frameworkId: "f", frameworkTitle: "F",
            mode: ranges.count == 1 ? EDLClip.modeContinuous : EDLClip.modeCompressedConcat,
            segments: ranges.map { EDLSegment(startSec: $0.0, endSec: $0.1, reason: nil) }, removedSegments: []
        )
    }

    @Test func compressesGapsIntoContiguousOutput() throws {
        let timeline = try ClipTimeline(clip: try clip([(1, 3), (5, 7), (10, 11)]))
        #expect(timeline.entries.map(\.compositionStart) == [0, 2, 4])
        #expect(timeline.entries[1] == TimelineEntry(sourceStart: 5, sourceEnd: 7, compositionStart: 2))
        #expect(timeline.entries[1].compositionEnd == 4)
        #expect(timeline.totalDuration == 5)
    }

    @Test func mapsSourceIntervalsAcrossGaps() throws {
        let timeline = try ClipTimeline(clip: try clip([(1, 3), (5, 7)]))
        let windows = timeline.compositionWindows(sourceStart: 2, sourceEnd: 6)
        #expect(windows.map(\.start) == [1, 2])
        #expect(windows.map(\.end) == [2, 3])
        #expect(timeline.compositionWindows(sourceStart: 3, sourceEnd: 5).isEmpty)
        #expect(timeline.compositionWindows(sourceStart: 0, sourceEnd: 1).isEmpty)
    }

    @Test func subtitleWindowsSplitStraddlingCues() throws {
        let timeline = try ClipTimeline(clip: try clip([(1, 3), (5, 7)]))
        let cues = [
            SRTCue(index: 1, start: 0, end: 1.5, text: "开头"),
            SRTCue(index: 2, start: 2.5, end: 5.5, text: "跨越"),
            SRTCue(index: 3, start: 3.2, end: 4.8, text: "删掉"),
        ]
        let windows = timeline.subtitleWindows(for: cues)
        #expect(windows == [
            SubtitleWindow(text: "开头", start: 0, end: 0.5),
            SubtitleWindow(text: "跨越", start: 1.5, end: 2),
            SubtitleWindow(text: "跨越", start: 2, end: 2.5),
        ])
    }

    // ADR-0023: captions rebuilt from timed words, with one window per spoken word.
    @Test func wordCaptionsFollowEachWordAndHoldThroughPauses() throws {
        let timeline = try ClipTimeline(clip: try clip([(1, 3), (5, 7)]))
        let cues = [SRTCue(index: 1, start: 1.0, end: 2.6, text: "先找话题 再动剪刀")]
        let words = [
            TimedToken(text: "先找话题", start: 1.1, end: 1.6),
            TimedToken(text: " ", start: 1.6, end: 1.6),
            TimedToken(text: "再动剪刀", start: 2.0, end: 2.6),
            TimedToken(text: "下一句", start: 2.7, end: 3.4),
        ]
        let captions = try timeline.wordCaptions(for: cues, words: words)
        #expect(captions.count == 1)
        let caption = try #require(captions.first)
        #expect(caption.text == "先找话题 再动剪刀")
        #expect(caption.start == 0 && caption.end == 1.6)
        // First word from the cue start (not its own start) until the next word starts; the pause 1.6–2.0 stays on it.
        #expect(caption.words == [
            WordWindow(range: 0..<4, start: 0, end: 1.0),
            WordWindow(range: 5..<9, start: 1.0, end: 1.6),
        ])
    }

    @Test func wordCaptionsSplitAtGapsAndKeepUTF16Ranges() throws {
        let timeline = try ClipTimeline(clip: try clip([(1, 3), (5, 7)]))
        let cues = [SRTCue(index: 1, start: 2.5, end: 5.5, text: "Today, we cut")]
        let words = [
            TimedToken(text: "Today, ", start: 2.5, end: 2.9), TimedToken(text: "we ", start: 2.9, end: 3.1),
            TimedToken(text: "cut", start: 5.1, end: 5.5),
        ]
        let captions = try timeline.wordCaptions(for: cues, words: words)
        #expect(captions.map(\.text) == ["Today, we cut", "Today, we cut"])
        #expect(captions.map(\.start) == [1.5, 2.0])
        #expect(captions.map(\.end) == [2.0, 2.5])
        #expect(captions[0].words == [WordWindow(range: 0..<6, start: 1.5, end: 1.9), WordWindow(range: 7..<9, start: 1.9, end: 2.0)])
        #expect(captions[1].words == [WordWindow(range: 7..<9, start: 2.0, end: 2.1), WordWindow(range: 10..<13, start: 2.1, end: 2.5)])
    }

    @Test func cueWithoutWordsInsideTheClipIsAnError() throws {
        let timeline = try ClipTimeline(clip: try clip([(1, 3)]))
        let cues = [SRTCue(index: 7, start: 1.2, end: 2.0, text: "没有词")]
        #expect(throws: ClipTimelineError.cueWithoutWords(cueIndex: 7)) {
            try timeline.wordCaptions(for: cues, words: [TimedToken(text: "别处", start: 8, end: 9)])
        }
        // A cue entirely outside the clip is skipped, words or not.
        #expect(try timeline.wordCaptions(for: [SRTCue(index: 8, start: 4, end: 5, text: "外面")], words: []).isEmpty)
    }
}
