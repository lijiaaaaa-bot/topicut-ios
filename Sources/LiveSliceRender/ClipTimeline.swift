// Why: rendering a compressed_concat clip means source time and output time diverge at every
// removed gap. This pure mapping is the one place that arithmetic lives, so composition insertion
// and subtitle placement cannot disagree, and it is unit-tested without touching AVFoundation.

import Foundation
import LiveSliceCore

public struct TimelineEntry: Equatable, Sendable {
    public let sourceStart: Double
    public let sourceEnd: Double
    public let compositionStart: Double

    public var duration: Double { sourceEnd - sourceStart }
    public var compositionEnd: Double { compositionStart + duration }
}

/// A subtitle to draw between two output (composition) times.
public struct SubtitleWindow: Equatable, Sendable {
    public let text: String
    public let start: Double
    public let end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

public struct ClipTimeline: Equatable, Sendable {
    public let entries: [TimelineEntry]

    /// Total output duration (sum of kept segments).
    public var totalDuration: Double { entries.reduce(0) { max($0, $1.compositionEnd) } }

    /// Builds the output timeline from a clip's kept segments (re-validating their invariants).
    public init(clip: EDLClip) throws {
        try EDLClip.validate(segments: clip.segments, clipID: clip.id)
        var cursor = 0.0
        var built: [TimelineEntry] = []
        for segment in clip.segments {
            built.append(TimelineEntry(sourceStart: segment.startSec, sourceEnd: segment.endSec, compositionStart: cursor))
            cursor += segment.endSec - segment.startSec
        }
        entries = built
    }

    /// Output windows covered by the source interval `[start, end)`; empty when it falls entirely in removed gaps.
    public func compositionWindows(sourceStart start: Double, sourceEnd end: Double) -> [(start: Double, end: Double)] {
        entries.compactMap { entry in
            let from = max(start, entry.sourceStart)
            let to = min(end, entry.sourceEnd)
            guard to > from else { return nil }
            let offset = entry.compositionStart - entry.sourceStart
            return (start: from + offset, end: to + offset)
        }
    }

    /// Maps subtitle cues (source time) onto output time, splitting cues that straddle a removed gap.
    public func subtitleWindows(for cues: [SRTCue]) -> [SubtitleWindow] {
        cues.flatMap { cue in
            compositionWindows(sourceStart: cue.start, sourceEnd: cue.end).map {
                SubtitleWindow(text: cue.text, start: $0.start, end: $0.end)
            }
        }
    }
}
