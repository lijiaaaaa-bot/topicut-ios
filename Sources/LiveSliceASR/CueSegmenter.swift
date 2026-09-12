// Why: SpeechTranscriber returns one long result per utterance with per-word time ranges; burnt-in
// subtitles and the LLM transcript both want short, sentence-shaped cues. This pure function does
// that grouping so it can be tested exhaustively without running speech recognition.

import Foundation
import LiveSliceCore

public enum CueSegmenterError: Error, Equatable, Sendable {
    /// Every token of a cue had zero duration; a subtitle cannot be shown for zero time.
    case nonPositiveCueDuration(text: String, start: Double, end: Double)
}

public struct CueSegmenterPolicy: Equatable, Sendable {
    public let maxCharacters: Int
    public let maxDurationSec: Double
    public let breakOnGapSec: Double
    public let sentenceEnders: Set<Character>

    public init(maxCharacters: Int, maxDurationSec: Double, breakOnGapSec: Double, sentenceEnders: Set<Character>) {
        self.maxCharacters = maxCharacters
        self.maxDurationSec = maxDurationSec
        self.breakOnGapSec = breakOnGapSec
        self.sentenceEnders = sentenceEnders
    }

    /// Tuned for Chinese speech: ~20 CJK characters per line, 6 s max on screen.
    /// Commas are break points because Chinese commas often mark breath groups.
    public static let chinese = CueSegmenterPolicy(
        maxCharacters: 22, maxDurationSec: 6.0, breakOnGapSec: 1.0,
        sentenceEnders: ["。", "！", "？", "!", "?", ".", "，", ",", "；", ";", "、"]
    )

    /// Tuned for English subtitles: ~40 Latin characters per line, no comma breaks
    /// (Apple inserts commas after openers like "Today,", which must not become solo cues).
    public static let english = CueSegmenterPolicy(
        maxCharacters: 42, maxDurationSec: 5.0, breakOnGapSec: 0.8,
        sentenceEnders: [".", "!", "?", "。", "！", "？"]
    )

    /// Historical alias used by older call sites and tests.
    public static let subtitle = chinese

    /// Picks the policy that matches the speech locale's primary language.
    public static func forLocale(_ locale: Locale) -> CueSegmenterPolicy {
        switch locale.language.languageCode?.identifier {
        case "en": return .english
        default: return .chinese
        }
    }
}

public enum CueSegmenter {
    /// Groups tokens into cues: a cue closes at sentence punctuation, when the next token would
    /// exceed the character or duration budget, or after a silence gap. Whitespace-only tokens are dropped.
    public static func cues(from tokens: [TimedToken], policy: CueSegmenterPolicy = .subtitle) throws -> [SRTCue] {
        var cues: [SRTCue] = []
        var current: [TimedToken] = []

        func flush() throws {
            guard let first = current.first else { return }
            let text = current.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            // SRT carries millisecond precision; round here so cues survive a write/parse round trip unchanged.
            let start = (first.start * 1000).rounded() / 1000
            let end = (current.reduce(first.end) { max($0, $1.end) } * 1000).rounded() / 1000
            if text.isEmpty { current = []; return }
            guard end > start else { throw CueSegmenterError.nonPositiveCueDuration(text: text, start: start, end: end) }
            cues.append(SRTCue(index: cues.count + 1, start: start, end: end, text: text))
            current = []
        }

        for token in tokens {
            if let first = current.first, let last = current.last {
                let chars = current.reduce(0) { $0 + $1.text.count } + token.text.count
                let duration = token.end - first.start
                let gap = token.start - last.end
                let endedSentence = last.text.last.map { policy.sentenceEnders.contains($0) } == true
                if endedSentence || chars > policy.maxCharacters || duration > policy.maxDurationSec || gap > policy.breakOnGapSec {
                    try flush()
                }
            }
            current.append(token)
        }
        try flush()
        return cues
    }
}
