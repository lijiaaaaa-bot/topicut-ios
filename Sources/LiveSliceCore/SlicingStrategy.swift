// Why: Slicing strategies define the mode (topic_complete) and domain (general default, military_news preset,
// or custom), pairing the prompt and EDL to a single source of truth for duration-adaptive clip counts.

import Foundation

/// Clip-count guidance handed to the prompt and recorded in the EDL.
public struct ClipCountPolicy: Codable, Equatable, Sendable {
    public let durationMinutes: Double
    public let minClips: Int
    public let maxClips: Int
    public let hardMaxClips: Int

    public init(durationMinutes: Double, minClips: Int, maxClips: Int, hardMaxClips: Int) {
        self.durationMinutes = durationMinutes
        self.minClips = minClips
        self.maxClips = maxClips
        self.hardMaxClips = hardMaxClips
    }
}

/// How many short quotable moments (金句) the same call should return alongside the topic clips.
/// Recorded in the EDL as `highlight_policy` (optional, ADR-0022).
public struct HighlightCountPolicy: Codable, Equatable, Sendable {
    public let durationMinutes: Double
    public let minHighlights: Int
    public let maxHighlights: Int
    /// Seconds a highlight should stay within; guidance for the model, not validated on output.
    public let minSeconds: Int
    public let maxSeconds: Int

    public init(durationMinutes: Double, minHighlights: Int, maxHighlights: Int, minSeconds: Int = 20, maxSeconds: Int = 90) {
        self.durationMinutes = durationMinutes
        self.minHighlights = minHighlights
        self.maxHighlights = maxHighlights
        self.minSeconds = minSeconds
        self.maxSeconds = maxSeconds
    }
}

public struct SlicingStrategy: Codable, Equatable, Sendable {
    /// One row of the duration → clip-count table. `maxMinutes == nil` means "and above".
    public struct DurationRange: Codable, Equatable, Sendable {
        public let maxMinutes: Double?
        public let minClips: Int
        public let maxClips: Int
        public let hardMaxClips: Int

        public init(maxMinutes: Double?, minClips: Int, maxClips: Int, hardMaxClips: Int) {
            self.maxMinutes = maxMinutes
            self.minClips = minClips
            self.maxClips = maxClips
            self.hardMaxClips = hardMaxClips
        }
    }

    public let mode: String
    public let domain: String
    public let durationRanges: [DurationRange]
    /// Hard cap on transcript characters sent to the LLM; longer input is an error, not a truncation.
    public let maxTranscriptChars: Int

    public init(mode: String, domain: String, durationRanges: [DurationRange], maxTranscriptChars: Int) {
        self.mode = mode
        self.domain = domain
        self.durationRanges = durationRanges
        self.maxTranscriptChars = maxTranscriptChars
    }

    public static let standardDurationRanges: [DurationRange] = [
        DurationRange(maxMinutes: 10, minClips: 1, maxClips: 3, hardMaxClips: 4),
        DurationRange(maxMinutes: 30, minClips: 3, maxClips: 7, hardMaxClips: 9),
        DurationRange(maxMinutes: 60, minClips: 5, maxClips: 10, hardMaxClips: 12),
        DurationRange(maxMinutes: nil, minClips: 6, maxClips: 14, hardMaxClips: 16),
    ]

    /// The default general-purpose topic-complete slicing strategy.
    public static let topicCompleteGeneral = SlicingStrategy(
        mode: "topic_complete",
        domain: "general",
        durationRanges: standardDurationRanges,
        maxTranscriptChars: 120_000
    )

    /// Preserved preset for specialized military news slicing.
    public static let topicCompleteMilitaryNews = SlicingStrategy(
        mode: "topic_complete",
        domain: "military_news",
        durationRanges: standardDurationRanges,
        maxTranscriptChars: 120_000
    )

    /// Factory for topic-complete slicing with custom domain.
    public static func topicComplete(domain: String = "general") -> SlicingStrategy {
        if domain == "military_news" {
            return .topicCompleteMilitaryNews
        }
        return SlicingStrategy(
            mode: "topic_complete",
            domain: domain,
            durationRanges: standardDurationRanges,
            maxTranscriptChars: 120_000
        )
    }

    /// Picks the first range whose `maxMinutes` covers the transcript duration.
    /// The last range must have `maxMinutes == nil`; a table without a catch-all is a programming error.
    public func clipCountPolicy(forDurationSeconds seconds: Double) throws -> ClipCountPolicy {
        let minutes = max(0.0, seconds) / 60.0
        for range in durationRanges {
            if let cap = range.maxMinutes, minutes > cap { continue }
            return ClipCountPolicy(
                durationMinutes: (minutes * 100).rounded() / 100,
                minClips: range.minClips,
                maxClips: max(range.minClips, range.maxClips),
                hardMaxClips: max(range.maxClips, range.hardMaxClips)
            )
        }
        throw SlicingStrategyError.noCatchAllRange(durationMinutes: minutes)
    }

    /// Highlight counts by duration: `(maxMinutes, min, max)`; the last row is the catch-all.
    /// Not part of the strategy's Codable shape so documents written before highlights still decode.
    static let standardHighlightRanges: [(maxMinutes: Double?, min: Int, max: Int)] = [
        (10, 2, 4), (30, 4, 8), (60, 6, 12), (nil, 10, 20),
    ]

    /// Highlight guidance for a transcript of `seconds`; same duration bands as clips, same
    /// catch-all rule (a table without one is a programming error, surfaced as the same typed error).
    public func highlightCountPolicy(forDurationSeconds seconds: Double) throws -> HighlightCountPolicy {
        let minutes = max(0.0, seconds) / 60.0
        for row in Self.standardHighlightRanges {
            if let cap = row.maxMinutes, minutes > cap { continue }
            return HighlightCountPolicy(durationMinutes: (minutes * 100).rounded() / 100, minHighlights: row.min, maxHighlights: row.max)
        }
        throw SlicingStrategyError.noCatchAllRange(durationMinutes: minutes)
    }
}

public enum SlicingStrategyError: Error, Equatable, Sendable {
    case noCatchAllRange(durationMinutes: Double)
}
