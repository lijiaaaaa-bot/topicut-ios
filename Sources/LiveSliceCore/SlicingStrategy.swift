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
}

public enum SlicingStrategyError: Error, Equatable, Sendable {
    case noCatchAllRange(durationMinutes: Double)
}
