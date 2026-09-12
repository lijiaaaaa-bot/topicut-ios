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

/// One word inside a caption: where it sits in the caption text (UTF-16 offsets) and when it is
/// the word being spoken, on the output clock.
public struct WordWindow: Equatable, Sendable {
    public let range: Range<Int>
    public let start: Double
    public let end: Double

    public init(range: Range<Int>, start: Double, end: Double) {
        self.range = range
        self.start = start
        self.end = end
    }
}

/// A caption rebuilt from its timed words: the text, its output window, and one WordWindow per
/// spoken word. Text comes from the words themselves so ranges and glyphs cannot disagree.
public struct WordCaption: Equatable, Sendable {
    public let text: String
    public let start: Double
    public let end: Double
    public let words: [WordWindow]

    public init(text: String, start: Double, end: Double, words: [WordWindow]) {
        self.text = text
        self.start = start
        self.end = end
        self.words = words
    }
}

public enum ClipTimelineError: Error, Equatable, Sendable, LocalizedError {
    /// A cue inside the clip has no timed word whose midpoint falls in it: the saved words and
    /// cues do not come from the same transcription.
    case cueWithoutWords(cueIndex: Int)

    public var errorDescription: String? {
        switch self {
        case .cueWithoutWords(let index): "第 \(index) 条字幕没有对应的词级时间，无法做高亮词字幕"
        }
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

    /// Captions with per-word timing for the cues inside this clip. `words` must be the tokens the
    /// cues were segmented from (same transcription); a cue with none is an error. A word stays
    /// highlighted until the next word starts, so pauses do not flash back to plain text.
    public func wordCaptions(for cues: [SRTCue], words: [TimedToken]) throws -> [WordCaption] {
        var captions: [WordCaption] = []
        var cursor = 0
        for cue in cues {
            while cursor < words.count, words[cursor].midpoint < cue.start { cursor += 1 }
            var inCue: [TimedToken] = []
            var scan = cursor
            while scan < words.count, words[scan].midpoint < cue.end { inCue.append(words[scan]); scan += 1 }
            cursor = scan
            let overlapping = entries.filter { min(cue.end, $0.sourceEnd) > max(cue.start, $0.sourceStart) }
            guard !overlapping.isEmpty else { continue }
            guard !inCue.isEmpty else { throw ClipTimelineError.cueWithoutWords(cueIndex: cue.index) }
            let (text, ranges) = Self.layout(inCue)
            let sourceWords = Self.wordWindows(inCue, ranges: ranges, cue: cue)
            for entry in overlapping {
                let from = max(cue.start, entry.sourceStart), to = min(cue.end, entry.sourceEnd)
                let offset = entry.compositionStart - entry.sourceStart
                let words = sourceWords
                    .filter { $0.end > from && $0.start < to }
                    .map { WordWindow(range: $0.range, start: Self.ms(max($0.start, from) + offset), end: Self.ms(min($0.end, to) + offset)) }
                captions.append(WordCaption(text: text, start: Self.ms(from + offset), end: Self.ms(to + offset), words: words))
            }
        }
        return captions
    }

    /// Millisecond precision, like SRT: keeps the offset arithmetic from leaving 2.0999999 behind.
    private static func ms(_ seconds: Double) -> Double { (seconds * 1000).rounded() / 1000 }

    /// Joins tokens into the caption text (outer whitespace trimmed, as CueSegmenter does) and
    /// returns each token's UTF-16 range in it; whitespace-only tokens get an empty range.
    private static func layout(_ tokens: [TimedToken]) -> (String, [Range<Int>]) {
        var pieces = tokens.map(\.text)
        if let first = pieces.first { pieces[0] = String(first.drop(while: \.isWhitespace)) }
        if let last = pieces.last {
            pieces[pieces.count - 1] = String(last.reversed().drop(while: \.isWhitespace).reversed())
        }
        var text = ""
        var ranges: [Range<Int>] = []
        for piece in pieces {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            let leading = piece.utf16.count - piece.drop(while: \.isWhitespace).utf16.count
            let from = text.utf16.count + leading
            ranges.append(from..<(from + trimmed.utf16.count))
            text += piece
        }
        return (text, ranges)
    }

    /// Source-time windows for the tokens of one cue: each word from its start (the first from the
    /// cue start) to the next word's start; whitespace-only tokens extend the previous word instead.
    private static func wordWindows(_ tokens: [TimedToken], ranges: [Range<Int>], cue: SRTCue) -> [WordWindow] {
        var result: [WordWindow] = []
        for (index, token) in tokens.enumerated() where !ranges[index].isEmpty {
            let start = index == 0 ? cue.start : max(cue.start, token.start)
            var end = cue.end
            var next = index + 1
            while next < tokens.count, ranges[next].isEmpty { next += 1 }
            if next < tokens.count { end = min(cue.end, max(start, tokens[next].start)) }
            if end > start { result.append(WordWindow(range: ranges[index], start: start, end: end)) }
        }
        return result
    }
}
