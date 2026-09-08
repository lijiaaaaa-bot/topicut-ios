import Foundation
import Testing
@testable import LiveSliceUI
import LiveSliceASR
import LiveSliceCore

/// Counts which pipeline steps actually ran.
actor StepCalls {
    var prepare = 0
    var transcribe = 0
    var slice = 0
    func prepared() { prepare += 1 }
    func transcribed() { transcribe += 1 }
    func sliced() { slice += 1 }
}

/// Reuse across imports and settings changes: nothing already computed for unchanged inputs runs again.
@MainActor
struct SliceSessionReuseTests {
    static let currentKey = PipelineReuse.sliceKey(model: DeepSeekConfiguration.defaultModel, baseURL: DeepSeekConfiguration.defaultBaseURL)

    static func counting(_ calls: StepCalls, locale: String = "zh_CN", title: String = "测试话题") -> SessionDependencies {
        SessionDependencies(
            prepareModel: { _, _ in await calls.prepared() },
            transcribe: { _, _, _, _ in
                await calls.transcribed()
                return TranscriptionOutcome(cues: SessionFixtures.cues, locale: Locale(identifier: locale))
            },
            slice: { _, _ in
                await calls.sliced()
                let clip = try SessionFixtures.clip()
                let retitled = try EDLClip(
                    id: clip.id, title: title, reason: clip.reason, score: clip.score, tags: clip.tags, category: clip.category,
                    frameworkId: clip.frameworkId, frameworkTitle: clip.frameworkTitle, mode: clip.mode,
                    segments: clip.segments, removedSegments: clip.removedSegments
                )
                let base = try SessionFixtures.document()
                return EDLDocument(
                    generatedAt: Date(timeIntervalSince1970: 0), strategy: base.strategy, clipCountPolicy: base.clipCountPolicy,
                    transcript: base.transcript, clips: [retitled], llm: nil
                )
            },
            render: { _, _, _, output, _ in
                try Data("mp4".utf8).write(to: output)
                return output
            }
        )
    }

    @Test func importingTheSameVideoAgainOpensTheExistingProject() async throws {
        let calls = StepCalls()
        let harness = try SessionHarness(Self.counting(calls))
        await harness.session.start(sourceURL: try harness.importedSource(named: "first.mov", contents: "same bytes"))
        #expect(harness.session.stage == .ready)
        let first = try #require(harness.session.projects.first)
        #expect(first.sourceFingerprint != nil)
        #expect(first.transcribedWith == "auto")
        #expect(first.slicedWith == Self.currentKey)

        let again = try harness.importedSource(named: "second.mov", contents: "same bytes")
        await harness.session.start(sourceURL: again)
        #expect(harness.session.stage == .ready)
        #expect(harness.session.projects.count == 1)
        #expect(harness.session.result?.projectID == first.id)
        #expect(!FileManager.default.fileExists(atPath: again.path), "the duplicate copy is discarded")
        #expect(await calls.transcribe == 1)
        #expect(await calls.slice == 1)
    }

    @Test func aDifferentVideoIsANewProject() async throws {
        let calls = StepCalls()
        let harness = try SessionHarness(Self.counting(calls))
        await harness.session.start(sourceURL: try harness.importedSource(named: "a.mov", contents: "video a"))
        await harness.session.start(sourceURL: try harness.importedSource(named: "b.mov", contents: "video b"))
        #expect(harness.session.projects.count == 2)
        #expect(await calls.transcribe == 2)
        #expect(await calls.slice == 2)
    }

    @Test func unchangedSettingsRunNothingOnOpen() async throws {
        let calls = StepCalls()
        let harness = try SessionHarness(Self.counting(calls))
        let record = try harness.savedProject(
            srt: try SRTWriter.serialize(SessionFixtures.cues), document: try SessionFixtures.document(),
            transcribedWith: "auto", slicedWith: Self.currentKey
        )
        await harness.session.open(record)
        #expect(harness.session.stage == .ready)
        #expect(await calls.prepare == 0)
        #expect(await calls.transcribe == 0)
        #expect(await calls.slice == 0)
    }

    @Test func changedModelReslicesKeepsTheTranscriptAndDropsOldExports() async throws {
        let calls = StepCalls()
        let harness = try SessionHarness(Self.counting(calls, title: "新模型的话题"))
        let record = try harness.savedProject(
            srt: try SRTWriter.serialize(SessionFixtures.cues), document: try SessionFixtures.document(),
            transcribedWith: "auto", slicedWith: Self.currentKey
        )
        let exports = harness.output.appending(path: record.id)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: exports.appending(path: "f_01_c_01.mp4"))

        harness.settings.model = "deepseek-reasoner"
        await harness.session.open(record)
        #expect(harness.session.stage == .ready)
        #expect(await calls.transcribe == 0)
        #expect(await calls.slice == 1)
        #expect(harness.session.result?.document.clips.first?.title == "新模型的话题")
        #expect(harness.session.renders.isEmpty, "exports cut from the old EDL must not pass for the new one")
        #expect(!FileManager.default.fileExists(atPath: exports.path))
        let saved = try harness.store.load(id: record.id)
        #expect(saved.slicedWith == PipelineReuse.sliceKey(model: "deepseek-reasoner", baseURL: DeepSeekConfiguration.defaultBaseURL))
        #expect(saved.transcribedWith == "auto")
    }

    @Test func changedLanguageSettingRerunsTranscriptionAndSlicing() async throws {
        let calls = StepCalls()
        let harness = try SessionHarness(Self.counting(calls, locale: "en_US"))
        let record = try harness.savedProject(
            srt: try SRTWriter.serialize(SessionFixtures.cues), document: try SessionFixtures.document(),
            transcribedWith: "auto", slicedWith: Self.currentKey
        )
        harness.settings.localeIdentifier = "en_US"
        await harness.session.open(record)
        #expect(harness.session.stage == .ready)
        #expect(await calls.transcribe == 1)
        #expect(await calls.slice == 1)
        let saved = try harness.store.load(id: record.id)
        #expect(saved.transcribedWith == "en_US")
        #expect(saved.localeIdentifier == "en_US")
        #expect(saved.slicedWith == Self.currentKey)
    }

    @Test func forcingTheLanguageTheTranscriptAlreadyHasReusesIt() async throws {
        let calls = StepCalls()
        let harness = try SessionHarness(Self.counting(calls))
        let record = try harness.savedProject(
            srt: try SRTWriter.serialize(SessionFixtures.cues), document: try SessionFixtures.document(),
            transcribedWith: "auto", slicedWith: Self.currentKey
        )
        harness.settings.localeIdentifier = "zh_CN" // what auto detected
        await harness.session.open(record)
        #expect(harness.session.stage == .ready)
        #expect(await calls.transcribe == 0)
        #expect(await calls.slice == 0)
    }
}
