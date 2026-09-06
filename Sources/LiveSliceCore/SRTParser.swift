// Why: the vertical slice starts from SRT text (later produced on-device by ASR); this is the
// single, strict entry point that turns SRT into cues and cues into the LLM transcript.
// Ported from live_slice_auto/live_slice/srt.py, made fail-fast: malformed blocks throw
// instead of being skipped.

import Foundation

public struct SRTCue: Equatable, Sendable {
    public let index: Int
    public let start: Double
    public let end: Double
    public let text: String

    public init(index: Int, start: Double, end: Double, text: String) {
        self.index = index
        self.start = start
        self.end = end
        self.text = text
    }
}

public enum SRTParseError: Error, Equatable, Sendable {
    /// A block has fewer than two non-empty lines (needs at least a time line and text).
    case malformedBlock(blockNumber: Int)
    /// The time line does not match `start --> end`.
    case invalidTimeLine(blockNumber: Int, line: String)
    /// A timestamp inside the time line is not `HH:MM:SS.mmm`.
    case invalidTimestamp(blockNumber: Int, value: String)
    /// `end <= start` for a cue.
    case nonPositiveDuration(blockNumber: Int, start: Double, end: Double)
    /// A block has a valid time line but no text.
    case emptyText(blockNumber: Int)
}

public enum SRTParser {
    /// Parses SRT text. Empty (whitespace-only) input yields an empty list.
    /// Cues are returned sorted by start time and re-indexed from 1.
    public static func parse(_ srt: String) throws -> [SRTCue] {
        let content = srt.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty { return [] }

        var cues: [SRTCue] = []
        var blockNumber = 0
        for block in splitBlocks(content) {
            blockNumber += 1
            let cue = try parseBlock(block, blockNumber: blockNumber)
            cues.append(cue)
        }
        let sorted = cues.sorted { $0.start < $1.start }
        return sorted.enumerated().map { offset, cue in
            SRTCue(index: offset + 1, start: cue.start, end: cue.end, text: cue.text)
        }
    }

    /// Renders cues as `[HH:MM:SS.mmm -> HH:MM:SS.mmm] text` lines for the LLM prompt.
    public static func plainTranscript(_ cues: [SRTCue]) -> String {
        cues.map { "[\(Timecode.format($0.start)) -> \(Timecode.format($0.end))] \($0.text)" }
            .joined(separator: "\n")
    }

    private static func splitBlocks(_ content: String) -> [[String]] {
        var blocks: [[String]] = []
        var current: [String] = []
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if !current.isEmpty { blocks.append(current); current = [] }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { blocks.append(current) }
        return blocks
    }

    private static func parseBlock(_ lines: [String], blockNumber: Int) throws -> SRTCue {
        guard lines.count >= 2 else { throw SRTParseError.malformedBlock(blockNumber: blockNumber) }
        let hasIndex = lines[0].allSatisfy(\.isNumber)
        let timeLineIndex = hasIndex ? 1 : 0
        guard lines.count > timeLineIndex else { throw SRTParseError.malformedBlock(blockNumber: blockNumber) }
        let (start, end) = try parseTimeLine(lines[timeLineIndex], blockNumber: blockNumber)
        let text = lines[(timeLineIndex + 1)...].joined(separator: "\n")
        guard !text.isEmpty else { throw SRTParseError.emptyText(blockNumber: blockNumber) }
        guard end > start else {
            throw SRTParseError.nonPositiveDuration(blockNumber: blockNumber, start: start, end: end)
        }
        return SRTCue(index: blockNumber, start: start, end: end, text: text)
    }

    private static func parseTimeLine(_ line: String, blockNumber: Int) throws -> (Double, Double) {
        let pieces = line.components(separatedBy: "-->")
        guard pieces.count == 2 else {
            throw SRTParseError.invalidTimeLine(blockNumber: blockNumber, line: line)
        }
        // SRT allows position hints after the end time ("00:00:01,000 X1:0"); drop them.
        let startRaw = pieces[0].trimmingCharacters(in: .whitespaces)
        let endRaw = pieces[1].trimmingCharacters(in: .whitespaces)
            .split(separator: " ", maxSplits: 1).first.map(String.init)
        guard let endRaw else {
            throw SRTParseError.invalidTimeLine(blockNumber: blockNumber, line: line)
        }
        return (
            try parseStamp(startRaw, blockNumber: blockNumber),
            try parseStamp(endRaw, blockNumber: blockNumber)
        )
    }

    private static func parseStamp(_ raw: String, blockNumber: Int) throws -> Double {
        do {
            return try Timecode.parse(raw)
        } catch TimecodeError.invalidTimestamp {
            throw SRTParseError.invalidTimestamp(blockNumber: blockNumber, value: raw)
        }
    }
}
