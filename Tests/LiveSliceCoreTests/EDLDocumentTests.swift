import Foundation
import Testing
@testable import LiveSliceCore

struct EDLDocumentTests {
    private func document(llm: LLMUsage? = TestSupport.sampleUsage) throws -> EDLDocument {
        EDLDocument(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            strategy: .topicCompleteMilitaryNews,
            clipCountPolicy: ClipCountPolicy(durationMinutes: 0.35, minClips: 1, maxClips: 3, hardMaxClips: 4),
            transcript: EDLTranscriptInfo(cueCount: 5, startSec: 1, endSec: 22),
            clips: [try TestSupport.clip()],
            llm: llm
        )
    }

    @Test func encodesSnakeCaseWithSchemaVersion() throws {
        let data = try document().encode()
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"schema_version\" : 1"))
        #expect(text.contains("\"start_sec\""))
        #expect(text.contains("\"removed_segments\""))
        #expect(text.contains("\"framework_id\""))
        #expect(text.contains("\"generated_at\" : \"2027-01-15T08:00:00Z\""))
        #expect(text.contains("\"domain\" : \"military_news\""))
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
}
