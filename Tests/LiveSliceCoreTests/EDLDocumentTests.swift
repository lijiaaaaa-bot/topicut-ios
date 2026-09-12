import Foundation
import LLMKit
import Testing
@testable import LiveSliceCore

struct EDLDocumentTests {
    private func document(llm: LLMUsage? = TestSupport.sampleUsage) throws -> EDLDocument {
        EDLDocument(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            strategy: .topicCompleteGeneral,
            clipCountPolicy: ClipCountPolicy(durationMinutes: 0.35, minClips: 1, maxClips: 3, hardMaxClips: 4),
            transcript: EDLTranscriptInfo(cueCount: 5, startSec: 1, endSec: 22),
            clips: [try TestSupport.clip()],
            llm: llm
        )
    }

    @Test func uniqueClipIDsCountPerFrameworkAcrossBlocks() {
        #expect(EDLClip.uniqueIDs(frameworkIDs: ["f_01", "f_01", "f_02", "f_01"]) == ["f_01_c_01", "f_01_c_02", "f_02_c_01", "f_01_c_03"])
        #expect(EDLClip.uniqueIDs(frameworkIDs: []).isEmpty)
    }

    @Test func withUniqueClipIDsRelabelsDuplicatesAndKeepsContent() throws {
        let first = try TestSupport.clip()
        let twin = try first.withID(first.id) // same id, second clip of the same framework
        let stale = EDLDocument(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000), strategy: .topicCompleteGeneral,
            clipCountPolicy: ClipCountPolicy(durationMinutes: 0.35, minClips: 1, maxClips: 3, hardMaxClips: 4),
            transcript: EDLTranscriptInfo(cueCount: 5, startSec: 1, endSec: 22),
            clips: [first, twin], llm: nil
        )
        let fixed = try stale.withUniqueClipIDs()
        #expect(fixed.clips.map(\.id) == ["\(first.frameworkId)_c_01", "\(first.frameworkId)_c_02"])
        #expect(fixed.clips.map(\.segments) == stale.clips.map(\.segments))
        #expect(fixed.generatedAt == stale.generatedAt)
        #expect(fixed.transcript == stale.transcript)
        // Already-unique documents come back identical.
        #expect(try document().withUniqueClipIDs() == document())
    }

    @Test func encodesSnakeCaseWithSchemaVersion() throws {
        let data = try document().encode()
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"schema_version\" : 1"))
        #expect(text.contains("\"start_sec\""))
        #expect(text.contains("\"removed_segments\""))
        #expect(text.contains("\"framework_id\""))
        #expect(text.contains("\"generated_at\" : \"2027-01-15T08:00:00Z\""))
        #expect(text.contains("\"domain\" : \"general\""))
        #expect(text.contains("\"llm\" : {"))
        #expect(text.contains("\"prompt_tokens\" : 1200"))
        #expect(text.contains("\"latency_ms\" : 0"))
    }

    @Test func llmMetadataIsOptionalForOlderDocuments() throws {
        // A document written before the `llm` field existed: same schema_version, no `llm` key.
        let legacy = String(decoding: try document(llm: nil).encode(), as: UTF8.self)
        #expect(!legacy.contains("\"llm\""))
        let decoded = try EDLDocument.decode(Data(legacy.utf8))
        #expect(decoded.llm == nil)
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.clips.count == 1)
    }

    @Test func roundTripsThroughJSON() throws {
        let original = try document()
        let decoded = try EDLDocument.decode(try original.encode())
        #expect(decoded == original)
        #expect(decoded.llm == TestSupport.sampleUsage)
    }

    @Test func rejectsMissingSchemaVersion() {
        let json = Data("{\"clips\": []}".utf8)
        #expect(throws: EDLDocumentError.missingSchemaVersion) { try EDLDocument.decode(json) }
    }

    @Test func rejectsUnknownSchemaVersion() {
        let json = Data("{\"schema_version\": 99, \"clips\": []}".utf8)
        #expect(throws: EDLDocumentError.unsupportedSchemaVersion(found: 99, supported: 1)) {
            try EDLDocument.decode(json)
        }
    }

    @Test func rejectsNonObjectAndBadBody() throws {
        #expect(throws: EDLDocumentError.self) { try EDLDocument.decode(Data("[1,2]".utf8)) }
        #expect(throws: EDLDocumentError.self) { try EDLDocument.decode(Data("{\"schema_version\": 1}".utf8)) }
    }

    @Test func revalidatesClipsAfterDecoding() throws {
        var text = String(decoding: try document().encode(), as: UTF8.self)
        text = text.replacingOccurrences(of: "\"score\" : 0.8", with: "\"score\" : 7")
        #expect(throws: EDLClipError.scoreOutOfRange(clipID: "f_01_c_01", score: 7)) {
            try EDLDocument.decode(Data(text.utf8))
        }
    }

    // ADR-0022: highlights are optional fields of the same schema version.
    private func quote(_ id: String = "highlights_c_01", score: Double = 0.9) throws -> EDLClip {
        try EDLClip(
            id: id, title: "一句判断", reason: "完整", score: score, tags: ["金句"], category: "金句",
            frameworkId: "highlights", frameworkTitle: "金句", mode: EDLClip.modeContinuous,
            segments: [TestSupport.segment(16, 22)], removedSegments: []
        )
    }

    @Test func highlightsRoundTripAndDistinguishNilFromEmpty() throws {
        let policy = HighlightCountPolicy(durationMinutes: 0.35, minHighlights: 2, maxHighlights: 4)
        let with = EDLDocument(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000), strategy: .topicCompleteGeneral,
            clipCountPolicy: ClipCountPolicy(durationMinutes: 0.35, minClips: 1, maxClips: 3, hardMaxClips: 4),
            transcript: EDLTranscriptInfo(cueCount: 5, startSec: 1, endSec: 22),
            clips: [try TestSupport.clip()], llm: nil, highlights: [try quote()], highlightPolicy: policy
        )
        let text = String(decoding: try with.encode(), as: UTF8.self)
        #expect(text.contains("\"highlights\" : ["))
        #expect(text.contains("\"highlight_policy\" : {"))
        #expect(text.contains("\"max_seconds\" : 90"))
        let decoded = try EDLDocument.decode(Data(text.utf8))
        #expect(decoded == with)
        #expect(decoded.highlights?.count == 1)

        let none = EDLDocument(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000), strategy: .topicCompleteGeneral,
            clipCountPolicy: with.clipCountPolicy, transcript: with.transcript,
            clips: with.clips, llm: nil, highlights: [], highlightPolicy: policy
        )
        #expect(try EDLDocument.decode(try none.encode()).highlights == [])

        // Written before the field existed: no key at all decodes to nil, not to [].
        let legacy = String(decoding: try document().encode(), as: UTF8.self)
        #expect(!legacy.contains("highlights"))
        #expect(try EDLDocument.decode(Data(legacy.utf8)).highlights == nil)
    }

    @Test func decodeRevalidatesHighlightsToo() throws {
        let policy = HighlightCountPolicy(durationMinutes: 0.35, minHighlights: 2, maxHighlights: 4)
        let doc = EDLDocument(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000), strategy: .topicCompleteGeneral,
            clipCountPolicy: ClipCountPolicy(durationMinutes: 0.35, minClips: 1, maxClips: 3, hardMaxClips: 4),
            transcript: EDLTranscriptInfo(cueCount: 5, startSec: 1, endSec: 22),
            clips: [try TestSupport.clip()], llm: nil, highlights: [try quote()], highlightPolicy: policy
        )
        var text = String(decoding: try doc.encode(), as: UTF8.self)
        text = text.replacingOccurrences(of: "\"score\" : 0.9", with: "\"score\" : 3")
        #expect(throws: EDLClipError.scoreOutOfRange(clipID: "highlights_c_01", score: 3)) {
            try EDLDocument.decode(Data(text.utf8))
        }
    }
}
