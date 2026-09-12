import Foundation
import Testing
@testable import LiveSliceCore

struct LLMResponseParserTests {
    @Test func parsesWellFormedReply() throws {
        let clips = try LLMResponseParser.parse(from: TestSupport.sampleLLMReply).clips
        #expect(clips.count == 1)
        let clip = clips[0]
        #expect(clip.id == "f_01_c_01")
        #expect(clip.frameworkId == "f_01")
        #expect(clip.frameworkTitle == "霍尔木兹海峡管控与美方航母部署")
        #expect(clip.mode == "compressed_concat")
        #expect(clip.segments.count == 2)
        #expect(clip.segments[1].reason == "主播分析与收束")
        #expect(clip.removedSegments.first?.reason == "答题互动")
        #expect(clip.category == "局势分析")
        #expect(clip.startSec == 1 && clip.endSec == 22)
    }

    @Test func stripsMarkdownFences() throws {
        let fenced = "```json\n\(TestSupport.sampleLLMReply)\n```"
        #expect(try LLMResponseParser.parse(from: fenced).clips.count == 1)
        let chatty = "好的，结果如下：\n\(TestSupport.sampleLLMReply)\n以上。"
        #expect(try LLMResponseParser.parse(from: chatty).clips.count == 1)
    }

    @Test func rejectsTextWithoutJSON() {
        #expect(throws: LLMResponseError.noJSONObject(preview: "抱歉，我无法处理。")) {
            try LLMResponseParser.parse(from: "抱歉，我无法处理。").clips
        }
    }

    @Test func rejectsMissingRequiredField() {
        let missingScore = TestSupport.sampleLLMReply.replacingOccurrences(of: "\"score\": 0.86,", with: "")
        #expect(throws: LLMResponseError.decoding("missing field 'score' at frameworks.Index 0.slices.Index 0")) {
            try LLMResponseParser.parse(from: missingScore).clips
        }
        let missingTags = TestSupport.sampleLLMReply.replacingOccurrences(of: "\"tags\": [\"军事新闻\", \"霍尔木兹\"],", with: "")
        #expect(throws: LLMResponseError.self) { try LLMResponseParser.parse(from: missingTags).clips }
    }

    @Test func rejectsEndNotAfterStartInsteadOfDropping() {
        let badRemoved = TestSupport.sampleLLMReply.replacingOccurrences(
            of: "{\"start\": \"00:00:13.000\", \"end\": \"00:00:16.000\", \"reason\": \"答题互动\"}",
            with: "{\"start\": \"00:00:13.000\", \"end\": \"00:00:13.000\", \"reason\": \"占位\"}"
        )
        #expect(throws: EDLClipError.nonPositiveDuration(clipID: "f_01_c_01", start: 13, end: 13)) {
            try LLMResponseParser.parse(from: badRemoved).clips
        }
        let badSegment = TestSupport.sampleLLMReply.replacingOccurrences(
            of: "{\"start\": \"00:00:16.000\", \"end\": \"00:00:22.000\"",
            with: "{\"start\": \"00:00:22.000\", \"end\": \"00:00:16.000\""
        )
        #expect(throws: EDLClipError.nonPositiveDuration(clipID: "f_01_c_01", start: 22, end: 16)) {
            try LLMResponseParser.parse(from: badSegment).clips
        }
    }

    @Test func rejectsOuterBoundaryDisagreeingWithSegments() {
        let drifted = TestSupport.llmReply(outerEnd: "00:00:40.000")
        #expect(throws: EDLClipError.outerBoundaryMismatch(clipID: "f_01_c_01")) {
            try LLMResponseParser.parse(from: drifted).clips
        }
    }

    @Test func rejectsRemovedSegmentOutsideClipInsteadOfTrimming() {
        let trailing = TestSupport.sampleLLMReply.replacingOccurrences(
            of: "{\"start\": \"00:00:13.000\", \"end\": \"00:00:16.000\", \"reason\": \"答题互动\"}",
            with: "{\"start\": \"00:00:13.000\", \"end\": \"00:00:16.000\", \"reason\": \"答题互动\"},"
                + "{\"start\": \"00:00:22.000\", \"end\": \"00:00:37.000\", \"reason\": \"下一题\"}"
        )
        #expect(throws: EDLClipError.removedSegmentOutsideClip(clipID: "f_01_c_01", removedIndex: 1)) {
            try LLMResponseParser.parse(from: trailing).clips
        }
    }

    @Test func repeatedFrameworkIDsStillYieldUniqueClipIDs() throws {
        // The model emitted the same framework twice; the second block's clips continue the numbering.
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(TestSupport.sampleLLMReply.utf8)) as? [String: Any]
        )
        let frameworks = try #require(object["frameworks"] as? [Any])
        let twice = try JSONSerialization.data(withJSONObject: ["frameworks": frameworks + frameworks, "highlights": []])

        let clips = try LLMResponseParser.parse(from: String(decoding: twice, as: UTF8.self)).clips
        #expect(clips.map(\.id) == ["f_01_c_01", "f_01_c_02"])
        #expect(Set(clips.map(\.id)).count == clips.count)
    }

    @Test func rejectsEmptyFrameworksAndInvalidTimestamps() {
        #expect(throws: LLMResponseError.noSlices) { try LLMResponseParser.parse(from: "{\"frameworks\": [], \"highlights\": []}").clips }
        let badStamp = TestSupport.sampleLLMReply.replacingOccurrences(of: "\"00:00:01.000\"", with: "\"0:01\"")
        #expect(throws: TimecodeError.invalidTimestamp("0:01")) { try LLMResponseParser.parse(from: badStamp).clips }
    }

    // ADR-0022: highlights ride along in the same reply.
    @Test func parsesHighlightsUnderTheirOwnFrameworkWithUniqueIDs() throws {
        let slices = try LLMResponseParser.parse(from: TestSupport.sampleLLMReply)
        #expect(slices.clips.count == 1)
        #expect(slices.highlights.count == 1)
        let quote = try #require(slices.highlights.first)
        #expect(quote.id == "highlights_c_01")
        #expect(quote.frameworkId == LLMResponseParser.highlightsFrameworkID)
        #expect(quote.frameworkTitle == "金句")
        #expect(quote.startSec == 16 && quote.endSec == 22)
        #expect(quote.category == "金句")
    }

    @Test func emptyHighlightsIsValidButMissingKeyIsNot() throws {
        let none = TestSupport.sampleLLMReply.replacingOccurrences(
            of: "\"highlights\": [", with: "\"highlights\": [], \"ignored\": ["
        )
        #expect(try LLMResponseParser.parse(from: none).highlights.isEmpty)
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(TestSupport.sampleLLMReply.utf8)) as? [String: Any]
        )
        let onlyFrameworks = try JSONSerialization.data(withJSONObject: ["frameworks": object["frameworks"]!])
        #expect(throws: LLMResponseError.decoding("missing field 'highlights' at <root>")) {
            try LLMResponseParser.parse(from: String(decoding: onlyFrameworks, as: UTF8.self))
        }
    }

    @Test func invalidHighlightRangeFailsTheWholeReply() {
        let bad = TestSupport.sampleLLMReply.replacingOccurrences(
            of: "{\"start\": \"00:00:16.000\", \"end\": \"00:00:22.000\", \"keep_reason\": \"完整表达\"}",
            with: "{\"start\": \"00:00:22.000\", \"end\": \"00:00:16.000\", \"keep_reason\": \"完整表达\"}"
        )
        #expect(throws: EDLClipError.self) { try LLMResponseParser.parse(from: bad) }
    }
}
