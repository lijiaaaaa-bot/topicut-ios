import Foundation
import Testing
@testable import LiveSliceCore

struct LLMResponseParserTests {
    @Test func parsesWellFormedReply() throws {
        let clips = try LLMResponseParser.parseClips(from: TestSupport.sampleLLMReply)
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
        #expect(try LLMResponseParser.parseClips(from: fenced).count == 1)
        let chatty = "好的，结果如下：\n\(TestSupport.sampleLLMReply)\n以上。"
        #expect(try LLMResponseParser.parseClips(from: chatty).count == 1)
    }

    @Test func rejectsTextWithoutJSON() {
        #expect(throws: LLMResponseError.noJSONObject(preview: "抱歉，我无法处理。")) {
            try LLMResponseParser.parseClips(from: "抱歉，我无法处理。")
        }
    }

    @Test func rejectsMissingRequiredField() {
        let missingScore = TestSupport.sampleLLMReply.replacingOccurrences(of: "\"score\": 0.86,", with: "")
        #expect(throws: LLMResponseError.decoding("missing field 'score' at frameworks.Index 0.slices.Index 0")) {
            try LLMResponseParser.parseClips(from: missingScore)
        }
        let missingTags = TestSupport.sampleLLMReply.replacingOccurrences(of: "\"tags\": [\"军事新闻\", \"霍尔木兹\"],", with: "")
        #expect(throws: LLMResponseError.self) { try LLMResponseParser.parseClips(from: missingTags) }
    }

    @Test func rejectsEndNotAfterStartInsteadOfDropping() {
        let badRemoved = TestSupport.sampleLLMReply.replacingOccurrences(
            of: "{\"start\": \"00:00:13.000\", \"end\": \"00:00:16.000\", \"reason\": \"答题互动\"}",
            with: "{\"start\": \"00:00:13.000\", \"end\": \"00:00:13.000\", \"reason\": \"占位\"}"
        )
        #expect(throws: EDLClipError.nonPositiveDuration(clipID: "f_01_c_01", start: 13, end: 13)) {
            try LLMResponseParser.parseClips(from: badRemoved)
        }
        let badSegment = TestSupport.sampleLLMReply.replacingOccurrences(
            of: "{\"start\": \"00:00:16.000\", \"end\": \"00:00:22.000\"",
            with: "{\"start\": \"00:00:22.000\", \"end\": \"00:00:16.000\""
        )
        #expect(throws: EDLClipError.nonPositiveDuration(clipID: "f_01_c_01", start: 22, end: 16)) {
            try LLMResponseParser.parseClips(from: badSegment)
        }
    }

    @Test func rejectsOuterBoundaryDisagreeingWithSegments() {
        let drifted = TestSupport.llmReply(outerEnd: "00:00:40.000")
        #expect(throws: EDLClipError.outerBoundaryMismatch(clipID: "f_01_c_01")) {
            try LLMResponseParser.parseClips(from: drifted)
        }
    }

    @Test func rejectsRemovedSegmentOutsideClipInsteadOfTrimming() {
        let trailing = TestSupport.sampleLLMReply.replacingOccurrences(
            of: "{\"start\": \"00:00:13.000\", \"end\": \"00:00:16.000\", \"reason\": \"答题互动\"}",
            with: "{\"start\": \"00:00:13.000\", \"end\": \"00:00:16.000\", \"reason\": \"答题互动\"},"
                + "{\"start\": \"00:00:22.000\", \"end\": \"00:00:37.000\", \"reason\": \"下一题\"}"
        )
        #expect(throws: EDLClipError.removedSegmentOutsideClip(clipID: "f_01_c_01", removedIndex: 1)) {
            try LLMResponseParser.parseClips(from: trailing)
        }
    }

    @Test func repeatedFrameworkIDsStillYieldUniqueClipIDs() throws {
        // The model emitted the same framework twice; the second block's clips continue the numbering.
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(TestSupport.sampleLLMReply.utf8)) as? [String: Any]
        )
        let frameworks = try #require(object["frameworks"] as? [Any])
        let twice = try JSONSerialization.data(withJSONObject: ["frameworks": frameworks + frameworks])

        let clips = try LLMResponseParser.parseClips(from: String(decoding: twice, as: UTF8.self))
        #expect(clips.map(\.id) == ["f_01_c_01", "f_01_c_02"])
        #expect(Set(clips.map(\.id)).count == clips.count)
    }

    @Test func rejectsEmptyFrameworksAndInvalidTimestamps() {
        #expect(throws: LLMResponseError.noSlices) { try LLMResponseParser.parseClips(from: "{\"frameworks\": []}") }
        let badStamp = TestSupport.sampleLLMReply.replacingOccurrences(of: "\"00:00:01.000\"", with: "\"0:01\"")
        #expect(throws: TimecodeError.invalidTimestamp("0:01")) { try LLMResponseParser.parseClips(from: badStamp) }
    }
}
