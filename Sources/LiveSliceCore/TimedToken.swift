// Why: SpeechTranscriber returns per-word audio time ranges; 1.0 collapsed them into sentence-shaped
// SRT cues and threw the word timing away. Word-highlight captions (ADR-0023) need the words back,
// so the token is a Core value type: produced by the ASR module, saved next to the transcript by the
// project store, and consumed by the renderer without either depending on the other.

import Foundation

/// One recognized token with its audio time range (seconds). Tokens without a time range attach to
/// the previous token before they reach the segmenter (see SpeechTranscriptionService).
public struct TimedToken: Codable, Equatable, Sendable {
    public let text: String
    public let start: Double
    public let end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }

    /// The instant a highlight belongs to this token: strictly inside its range, so tokens that
    /// touch at a shared boundary never both claim it.
    public var midpoint: Double { (start + end) / 2 }
}
