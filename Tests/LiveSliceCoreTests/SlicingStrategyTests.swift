import Testing
@testable import LiveSliceCore

struct SlicingStrategyTests {
    @Test func defaultIsTopicCompleteGeneral() {
        let strategy = SlicingStrategy.topicCompleteGeneral
        #expect(strategy.mode == "topic_complete")
        #expect(strategy.domain == "general")
        #expect(strategy.durationRanges.last?.maxMinutes == nil)
    }

    @Test func militaryNewsPresetIsPreserved() {
        let strategy = SlicingStrategy.topicCompleteMilitaryNews
        #expect(strategy.mode == "topic_complete")
        #expect(strategy.domain == "military_news")
        #expect(strategy.durationRanges.last?.maxMinutes == nil)
    }

    @Test func customDomainFactory() {
        let podcast = SlicingStrategy.topicComplete(domain: "podcast")
        #expect(podcast.mode == "topic_complete")
        #expect(podcast.domain == "podcast")

        let military = SlicingStrategy.topicComplete(domain: "military_news")
        #expect(military == .topicCompleteMilitaryNews)
    }

    struct Row {
        let seconds: Double
        let expected: (Int, Int, Int)
    }

    static let rows: [Row] = [
        Row(seconds: 300, expected: (1, 3, 4)),
        Row(seconds: 600, expected: (1, 3, 4)),
        Row(seconds: 1500, expected: (3, 7, 9)),
        Row(seconds: 2700, expected: (5, 10, 12)),
        Row(seconds: 10800, expected: (6, 14, 16)),
    ]

    @Test func picksRangeByDuration() throws {
        for row in Self.rows {
            let policy = try SlicingStrategy.topicCompleteGeneral.clipCountPolicy(forDurationSeconds: row.seconds)
            #expect((policy.minClips, policy.maxClips, policy.hardMaxClips) == row.expected, "seconds=\(row.seconds)")
            #expect(policy.durationMinutes == (row.seconds / 60 * 100).rounded() / 100)
        }
    }

    @Test func tableWithoutCatchAllThrows() {
        let strategy = SlicingStrategy(
            mode: "topic_complete", domain: "general",
            durationRanges: [SlicingStrategy.DurationRange(maxMinutes: 10, minClips: 1, maxClips: 2, hardMaxClips: 3)],
            maxTranscriptChars: 100
        )
        #expect(throws: SlicingStrategyError.noCatchAllRange(durationMinutes: 20)) {
            try strategy.clipCountPolicy(forDurationSeconds: 1200)
        }
    }
}
