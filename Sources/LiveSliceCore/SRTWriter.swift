// Why: on-device ASR produces cues, but the slicing contract (TopicSlicer) takes SRT text. One
// strict serializer keeps that boundary textual and round-trippable through SRTParser, so the
// app and the CLI feed the LLM byte-identical transcripts for the same speech.

import Foundation

public enum SRTWriterError: Error, Equatable, Sendable {
    /// A cue has `end <= start`; SRTParser would reject the output, so we refuse to write it.
    case nonPositiveDuration(index: Int, start: Double, end: Double)
    /// A cue has no text; SRTParser would reject the output.
    case emptyText(index: Int)
}

public enum SRTWriter {
    /// Serializes cues as standard SRT (`HH:MM:SS,mmm --> HH:MM:SS,mmm`), re-indexed from 1 in
    /// start-time order. Output parses back with `SRTParser.parse` to the same times and texts.
    public static func serialize(_ cues: [SRTCue]) throws -> String {
        let ordered = cues.sorted { $0.start < $1.start }
        var blocks: [String] = []
        for (offset, cue) in ordered.enumerated() {
            let index = offset + 1
            guard cue.end > cue.start else {
                throw SRTWriterError.nonPositiveDuration(index: index, start: cue.start, end: cue.end)
            }
            let text = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw SRTWriterError.emptyText(index: index) }
            let start = Timecode.format(cue.start).replacingOccurrences(of: ".", with: ",")
            let end = Timecode.format(cue.end).replacingOccurrences(of: ".", with: ",")
            blocks.append("\(index)\n\(start) --> \(end)\n\(text)")
        }
        return blocks.joined(separator: "\n\n") + (blocks.isEmpty ? "" : "\n")
    }
}
