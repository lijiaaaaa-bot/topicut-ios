// Why: shared offline fixtures (sample SRT, canned DeepSeek replies, stub transport) so no test
// ever touches the network and every test file stays focused on its own module.

import Foundation
@testable import LiveSliceCore

enum TestSupport {
    static let sampleSRT = """
    1
    00:00:01,000 --> 00:00:04,500
    今天先看第一件事，伊朗宣布对霍尔木兹海峡实施临时管控。

    2
    00:00:04,500 --> 00:00:09,000
    这条海峡承担全球大约五分之一的海运原油，
    任何风吹草动都会直接传导到油价。

    3
    00:00:09,000 --> 00:00:13,000
    美方随即宣布把第二支航母打击群调往阿拉伯海。

    4
    00:00:13,000 --> 00:00:16,000
    好，咱们看看第二道题，答对的自己领钱。

    5
    00:00:16,000 --> 00:00:22,000
    回到正题，这次部署更像是威慑姿态，而不是地面战的前奏。
    """

    /// A well-formed DeepSeek reply: one framework, one compressed_concat clip skipping the quiz cue.
    static let sampleLLMReply = llmReply()

    /// Same reply with a configurable outer `end`, so tests can make it disagree with the segments.
    static func llmReply(outerEnd: String = "00:00:22.000") -> String {
    """
    {
      "frameworks": [
        {
          "id": "f_01",
          "title": "霍尔木兹海峡管控与美方航母部署",
          "slices": [
            {
              "title": "伊朗管控霍尔木兹_美方航母调动是威慑而非开战",
              "reason": "事件开场→背景→美方应对→主播判断，链条完整",
              "start": "00:00:01.000",
              "end": "\(outerEnd)",
              "mode": "compressed_concat",
              "score": 0.86,
              "category": "局势分析",
              "tags": ["军事新闻", "霍尔木兹"],
              "segments": [
                {"start": "00:00:01.000", "end": "00:00:13.000", "keep_reason": "话题主体"},
                {"start": "00:00:16.000", "end": "00:00:22.000", "keep_reason": "主播分析与收束"}
              ],
              "removed_segments": [
                {"start": "00:00:13.000", "end": "00:00:16.000", "reason": "答题互动"}
              ]
            }
          ]
        }
      ]
    }
    """
    }

    static func configuration() throws -> DeepSeekConfiguration {
        try DeepSeekConfiguration(apiKey: "test-key-not-real", baseURL: "https://example.invalid", model: "test-model")
    }

    static let sampleUsage = LLMUsage(model: "test-model", promptTokens: 1200, completionTokens: 340, totalTokens: 1540, latencyMs: 0)

    /// Wraps `content` in the OpenAI-compatible chat completion envelope (with `usage` unless told otherwise).
    static func chatEnvelope(content: String, includeUsage: Bool = true) -> Data {
        var body: [String: Any] = [
            "choices": [["message": ["role": "assistant", "content": content]]],
        ]
        if includeUsage {
            body["usage"] = [
                "prompt_tokens": sampleUsage.promptTokens,
                "completion_tokens": sampleUsage.completionTokens,
                "total_tokens": sampleUsage.totalTokens,
            ]
        }
        // JSONSerialization on a literal dictionary cannot fail; if it ever does, crash loudly rather than return junk.
        do {
            return try JSONSerialization.data(withJSONObject: body)
        } catch {
            preconditionFailure("fixture encoding failed: \(error)")
        }
    }

    /// A transport that records the request and returns a fixed HTTP response.
    static func stubTransport(status: Int, body: Data) -> DeepSeekClient.Transport {
        { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
            else { preconditionFailure("stub transport needs a URL") }
            return (body, response)
        }
    }

    static func segment(_ start: Double, _ end: Double, reason: String? = nil) -> EDLSegment {
        EDLSegment(startSec: start, endSec: end, reason: reason)
    }

    static func clip(
        id: String = "f_01_c_01",
        segments: [EDLSegment] = [segment(1, 13), segment(16, 22)],
        removed: [EDLSegment] = [segment(13, 16, reason: "答题互动")],
        score: Double = 0.8,
        mode: String = EDLClip.modeCompressedConcat,
        title: String = "测试话题"
    ) throws -> EDLClip {
        try EDLClip(
            id: id, title: title, reason: "完整", score: score, tags: ["军事新闻"], category: "局势分析",
            frameworkId: "f_01", frameworkTitle: "框架", mode: mode, segments: segments, removedSegments: removed
        )
    }
}
