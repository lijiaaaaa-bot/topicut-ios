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
}
