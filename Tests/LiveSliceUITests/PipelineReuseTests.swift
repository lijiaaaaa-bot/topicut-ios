import Foundation
import Testing
@testable import LiveSliceUI
import LiveSliceASR
import LiveSliceCore

struct PipelineReuseTests {
    private func record(
        srt: String? = "1\n00:00:01,000 --> 00:00:02,000\n你好\n", locale: String? = "zh_CN", transcribedWith: String?,
        document: EDLDocument? = nil, slicedWith: String? = nil
    ) -> ProjectRecord {
        ProjectRecord(
            id: "p", createdAt: Date(timeIntervalSince1970: 0), sourceFileName: "source.mov",
            localeIdentifier: locale, srt: srt, transcribedWith: transcribedWith, document: document, slicedWith: slicedWith
        )
    }

    @Test func sliceKeyIgnoresTheAPIKeyAndSurroundingSpaces() {
        #expect(PipelineReuse.sliceKey(model: "deepseek-v4-flash", baseURL: "https://api.deepseek.com") == "deepseek-v4-flash|https://api.deepseek.com")
        #expect(PipelineReuse.sliceKey(model: " deepseek-v4-flash ", baseURL: "https://api.deepseek.com ") == "deepseek-v4-flash|https://api.deepseek.com")
        #expect(PipelineReuse.sliceKey(model: "deepseek-v4-pro", baseURL: "https://api.deepseek.com") != PipelineReuse.sliceKey(model: "deepseek-v4-flash", baseURL: "https://api.deepseek.com"))
    }

    @Test func sliceKeyTreatsTheRetiredAliasAsTheModelItStoodFor() throws {
        let old = PipelineReuse.sliceKey(model: "deepseek-chat", baseURL: "https://api.deepseek.com")
        #expect(old == "deepseek-v4-flash|https://api.deepseek.com")
        // A project sliced under the old default is still current under the new default.
        let record = record(transcribedWith: "auto", document: try SessionFixtures.document(), slicedWith: old)
        #expect(PipelineReuse.sliceIsCurrent(record, transcriptCurrent: true, key: PipelineReuse.sliceKey(model: "deepseek-v4-flash", baseURL: "https://api.deepseek.com")))
        // Other names are passed through untouched.
        #expect(PipelineReuse.sliceKey(model: "qwen-plus", baseURL: "https://x.example/v1") == "qwen-plus|https://x.example/v1")
    }

    @Test func transcriptNeedsASavedSRTAndLocale() {
        #expect(!PipelineReuse.transcriptIsCurrent(record(srt: nil, transcribedWith: "auto"), preference: .automatic))
        #expect(!PipelineReuse.transcriptIsCurrent(record(locale: nil, transcribedWith: "auto"), preference: .automatic))
    }

    @Test func transcriptStandsForTheSamePreference() {
        #expect(PipelineReuse.transcriptIsCurrent(record(transcribedWith: "auto"), preference: .automatic))
        #expect(PipelineReuse.transcriptIsCurrent(record(transcribedWith: "zh_CN"), preference: .fixed(Locale(identifier: "zh_CN"))))
    }

    @Test func fixedPreferenceMatchingTheProducedLocaleStandsOtherChangesRerun() {
        // Detected zh_CN under auto; now forced to zh_CN: the same transcript would come out again.
        #expect(PipelineReuse.transcriptIsCurrent(record(transcribedWith: "auto"), preference: .fixed(Locale(identifier: "zh_CN"))))
        // Forced to en_US: a different language model must run.
        #expect(!PipelineReuse.transcriptIsCurrent(record(transcribedWith: "auto"), preference: .fixed(Locale(identifier: "en_US"))))
        // Produced under a fixed locale; now auto: detection might choose differently, so rerun.
        #expect(!PipelineReuse.transcriptIsCurrent(record(transcribedWith: "zh_CN"), preference: .automatic))
    }

    @Test func legacyRecordsWithoutProvenanceAreKept() throws {
        let legacy = record(transcribedWith: nil, document: try SessionFixtures.document(), slicedWith: nil)
        #expect(PipelineReuse.transcriptIsCurrent(legacy, preference: .fixed(Locale(identifier: "en_US"))))
        #expect(PipelineReuse.sliceIsCurrent(legacy, transcriptCurrent: true, key: "anything|anywhere"))
    }

    @Test func sliceNeedsACurrentTranscriptAndTheSameModelAndEndpoint() throws {
        let key = PipelineReuse.sliceKey(model: "deepseek-v4-flash", baseURL: "https://api.deepseek.com")
        let sliced = record(transcribedWith: "auto", document: try SessionFixtures.document(), slicedWith: key)
        #expect(PipelineReuse.sliceIsCurrent(sliced, transcriptCurrent: true, key: key))
        #expect(!PipelineReuse.sliceIsCurrent(sliced, transcriptCurrent: false, key: key))
        #expect(!PipelineReuse.sliceIsCurrent(sliced, transcriptCurrent: true, key: "deepseek-v4-pro|https://api.deepseek.com"))
        #expect(!PipelineReuse.sliceIsCurrent(record(transcribedWith: "auto"), transcriptCurrent: true, key: key))
    }
}
