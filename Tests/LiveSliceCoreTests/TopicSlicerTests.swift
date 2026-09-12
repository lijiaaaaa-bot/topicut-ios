import Foundation
import LLMKit
import Testing
@testable import LiveSliceCore

struct TopicSlicerTests {
    private func slicer(reply: String, strategy: SlicingStrategy = .topicCompleteGeneral) throws -> TopicSlicer {
        let client = DeepSeekClient(
            configuration: try TestSupport.configuration(),
            transport: TestSupport.stubTransport(status: 200, body: TestSupport.chatEnvelope(content: reply))
        )
        return TopicSlicer(client: client, strategy: strategy)
    }

    @Test func producesEDLFromSRTAndCannedReply() async throws {
        let document = try await slicer(reply: TestSupport.sampleLLMReply).slice(srtText: TestSupport.sampleSRT)
        #expect(document.schemaVersion == 1)
        #expect(document.clips.count == 1)
        #expect(document.transcript == EDLTranscriptInfo(cueCount: 5, startSec: 1, endSec: 22))
        #expect(document.clipCountPolicy.minClips == 1 && document.clipCountPolicy.maxClips == 3)
        #expect(document.strategy == .topicCompleteGeneral)
        #expect(document.llm?.model == "test-model")
        #expect(document.llm?.totalTokens == 1540)
        #expect(document.highlights?.map(\.id) == ["highlights_c_01"])
        #expect(document.highlightPolicy == HighlightCountPolicy(durationMinutes: 0.35, minHighlights: 2, maxHighlights: 4))
        let decoded = try EDLDocument.decode(try document.encode())
        #expect(decoded == document)
    }

    @Test func highlightOutsideSubtitleRangeIsRejectedLikeAClip() async throws {
        var object = try #require(
            try JSONSerialization.jsonObject(with: Data(TestSupport.sampleLLMReply.utf8)) as? [String: Any]
        )
        var quotes = try #require(object["highlights"] as? [[String: Any]])
        quotes[0]["end"] = "00:00:40.000"
        quotes[0]["segments"] = [["start": "00:00:16.000", "end": "00:00:40.000", "keep_reason": "完整表达"]]
        object["highlights"] = quotes
        let late = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        await #expect(throws: TopicSlicerError.clipOutOfBounds(
            clipID: "highlights_c_01", startSec: 16, endSec: 40, transcriptStart: 1, transcriptEnd: 22
        )) {
            try await slicer(reply: late).slice(srtText: TestSupport.sampleSRT)
        }
    }

    @Test func missingUsageFailsTheWholeRun() async throws {
        let client = DeepSeekClient(
            configuration: try TestSupport.configuration(),
            transport: TestSupport.stubTransport(
                status: 200, body: TestSupport.chatEnvelope(content: TestSupport.sampleLLMReply, includeUsage: false)
            )
        )
        await #expect(throws: DeepSeekError.self) {
            try await TopicSlicer(client: client).slice(srtText: TestSupport.sampleSRT)
        }
    }

    @Test func emptyTranscriptFailsBeforeNetwork() async throws {
        let client = DeepSeekClient(configuration: try TestSupport.configuration()) { _ in
            preconditionFailure("network must not be touched for empty input")
        }
        await #expect(throws: TopicSlicerError.emptyTranscript) {
            try await TopicSlicer(client: client).slice(srtText: "\n\n")
        }
    }

    @Test func oversizedTranscriptFailsInsteadOfTruncating() async throws {
        let tiny = SlicingStrategy(
            mode: "topic_complete", domain: "general",
            durationRanges: SlicingStrategy.topicCompleteGeneral.durationRanges, maxTranscriptChars: 10
        )
        await #expect(throws: TopicSlicerError.self) {
            try await slicer(reply: TestSupport.sampleLLMReply, strategy: tiny).slice(srtText: TestSupport.sampleSRT)
        }
    }

    @Test func clipOutsideSubtitleRangeIsRejected() async throws {
        let shifted = TestSupport.sampleLLMReply
            .replacingOccurrences(of: "00:00:22.000", with: "00:00:30.000")
        await #expect(throws: TopicSlicerError.self) {
            try await slicer(reply: shifted).slice(srtText: TestSupport.sampleSRT)
        }
    }

    @Test func llmErrorsPropagateUnchanged() async throws {
        let client = DeepSeekClient(
            configuration: try TestSupport.configuration(),
            transport: TestSupport.stubTransport(status: 500, body: Data("internal error".utf8))
        )
        await #expect(throws: DeepSeekError.self) {
            try await TopicSlicer(client: client).slice(srtText: TestSupport.sampleSRT)
        }
    }
}
