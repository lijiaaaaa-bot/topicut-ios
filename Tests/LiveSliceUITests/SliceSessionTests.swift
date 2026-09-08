import Foundation
import Testing
@testable import LiveSliceUI
import LiveSliceASR
import LiveSliceCore
import LiveSliceKeychain
import Photos

@MainActor
struct SliceSessionTests {
    static func dependencies(
        transcribeError: Error? = nil, sliceError: Error? = nil, renderError: Error? = nil
    ) -> SessionDependencies {
        SessionDependencies(
            prepareModel: { preference, progress in
                #expect(preference == .automatic)
                progress(1)
            },
            transcribe: { _, preference, _, progress in
                if let transcribeError { throw transcribeError }
                #expect(preference == .automatic)
                progress(0.5)
                return TranscriptionOutcome(cues: SessionFixtures.cues, locale: Locale(identifier: "zh_CN"))
            },
            slice: { srt, configuration in
                if let sliceError { throw sliceError }
                #expect(configuration.apiKey == "sk-test")
                #expect(try SRTParser.parse(srt) == SessionFixtures.cues)
                return try SessionFixtures.document()
            },
            render: { _, clip, cues, output, progress in
                if let renderError { throw renderError }
                #expect(clip.id == "f_01_c_01")
                #expect(cues.count == 2)
                progress(0.7)
                try Data("mp4".utf8).write(to: output)
                return output
            }
        )
    }

    @Test func happyPathReachesReadyAndRendersClip() async throws {
        let harness = try SessionHarness(Self.dependencies())
        let session = harness.session
        let idle: SessionStage = session.stage
        #expect(idle == .idle)
        await session.start(sourceURL: try harness.importedSource())
        #expect(session.stage == .ready)
        let result: SessionResult = try #require(session.result)
        #expect(result.document.clips.count == 1)
        #expect(result.cues == SessionFixtures.cues)
        #expect(result.localeIdentifier == "zh_CN")
        #expect(session.activeLocaleIdentifier == "zh_CN")

        let clip = try SessionFixtures.clip()
        await session.render(clip: clip)
        guard case .done(let url) = session.renders[clip.id] else {
            Issue.record("expected .done, got \(String(describing: session.renders[clip.id]))")
            return
        }
        #expect(url.lastPathComponent == "f_01_c_01.mp4")
        #expect(url.deletingLastPathComponent().lastPathComponent == result.projectID)
        #expect(!session.isWorking)
    }

    @Test func startAdoptsTheSourceIntoAProjectAndCheckpointsEachStep() async throws {
        let harness = try SessionHarness(Self.dependencies())
        let picked = try harness.importedSource()
        let stale = try harness.importedSource(named: "stale.mov")
        await harness.session.start(sourceURL: picked)
        #expect(harness.session.stage == .ready)

        let record = try #require(harness.session.projects.first)
        #expect(harness.session.projects.count == 1)
        #expect(!FileManager.default.fileExists(atPath: picked.path))
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: harness.store.sourceURL(of: record).path))
        #expect(harness.session.result?.sourceURL == harness.store.sourceURL(of: record))
        let saved = try harness.store.load(id: record.id)
        #expect(try SRTParser.parse(try #require(saved.srt)) == SessionFixtures.cues)
        #expect(saved.localeIdentifier == "zh_CN")
        #expect(saved.document == (try SessionFixtures.document()))
        #expect(saved.title == "测试话题")
        #expect(saved.clipCount == 1)
    }

    @Test func openSlicedProjectIsReadyWithoutRunningThePipeline() async throws {
        let harness = try SessionHarness(Self.dependencies(
            transcribeError: SessionTestError.mustNotRun, sliceError: SessionTestError.mustNotRun
        ), key: nil)
        let record = try harness.savedProject(
            srt: try SRTWriter.serialize(SessionFixtures.cues), document: try SessionFixtures.document()
        )
        await harness.session.open(record)
        #expect(harness.session.stage == .ready)
        #expect(harness.session.result?.cues == SessionFixtures.cues)
        #expect(harness.session.result?.projectID == record.id)
        #expect(harness.session.activeLocaleIdentifier == "zh_CN")
    }

    @Test func openTranscribedProjectResumesAtSlicing() async throws {
        let harness = try SessionHarness(Self.dependencies(transcribeError: SessionTestError.mustNotRun))
        let record = try harness.savedProject(srt: try SRTWriter.serialize(SessionFixtures.cues))
        #expect(!record.isSliced && record.isTranscribed)
        await harness.session.open(record)
        #expect(harness.session.stage == .ready)
        #expect(try harness.store.load(id: record.id).document == (try SessionFixtures.document()))
    }

    /// Projects sliced before the unique-id rule can hold two clips with one id; opening them
    /// relabels the clips once and writes the corrected document back.
    @Test func openRelabelsDuplicateClipIDsAndPersistsTheFix() async throws {
        let harness = try SessionHarness(Self.dependencies())
        let strategy = SlicingStrategy.topicCompleteGeneral
        let twin = try EDLClip(
            id: "f_01_c_01", title: "同号话题", reason: "完整", score: 0.7, tags: [], category: nil,
            frameworkId: "f_01", frameworkTitle: "框架", mode: EDLClip.modeContinuous,
            segments: [EDLSegment(startSec: 16, endSec: 22, reason: nil)], removedSegments: []
        )
        let stale = EDLDocument(
            generatedAt: Date(timeIntervalSince1970: 0), strategy: strategy,
            clipCountPolicy: try strategy.clipCountPolicy(forDurationSeconds: 21),
            transcript: EDLTranscriptInfo(cueCount: 2, startSec: 1, endSec: 22),
            clips: [try SessionFixtures.clip(), twin], llm: nil
        )
        let record = try harness.savedProject(srt: try SRTWriter.serialize(SessionFixtures.cues), document: stale)

        await harness.session.open(record)
        #expect(harness.session.stage == .ready)
        let ids = harness.session.result?.document.clips.map(\.id)
        #expect(ids == ["f_01_c_01", "f_01_c_02"])
        #expect(harness.session.result?.document.clips.map(\.title) == ["测试话题", "同号话题"])
        #expect(try harness.store.load(id: record.id).document?.clips.map(\.id) == ["f_01_c_01", "f_01_c_02"])
    }

    @Test func openRestoresExportsAlreadyOnDisk() async throws {
        let harness = try SessionHarness(Self.dependencies())
        let record = try harness.savedProject(
            srt: try SRTWriter.serialize(SessionFixtures.cues), document: try SessionFixtures.document()
        )
        let exports = harness.output.appending(path: record.id)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        let file = exports.appending(path: "f_01_c_01.mp4")
        try Data("mp4".utf8).write(to: file)
        try Data("junk".utf8).write(to: exports.appending(path: "unrelated.mp4"))

        await harness.session.open(record)
        guard case .done(let restored) = harness.session.renders["f_01_c_01"] else {
            Issue.record("expected .done, got \(String(describing: harness.session.renders["f_01_c_01"]))")
            return
        }
        // /var vs /private/var: the temp directory is reached through a symlink on macOS.
        #expect(restored.resolvingSymlinksInPath() == file.resolvingSymlinksInPath())
        #expect(harness.session.renders.count == 1)
    }

    @Test func openWithoutSourceVideoFails() async throws {
        let harness = try SessionHarness(Self.dependencies())
        let record = try harness.savedProject(srt: try SRTWriter.serialize(SessionFixtures.cues), source: false)
        await harness.session.open(record)
        #expect(harness.session.stage == .failed("项目 \(record.id) 的源视频已不在设备上"))
    }

    @Test func deleteRemovesProjectSourceAndExports() async throws {
        let harness = try SessionHarness(Self.dependencies())
        await harness.session.start(sourceURL: try harness.importedSource())
        await harness.session.render(clip: try SessionFixtures.clip())
        let record = try #require(harness.session.projects.first)
        let exports = harness.output.appending(path: record.id)
        #expect(FileManager.default.fileExists(atPath: exports.path))

        harness.session.delete(record)
        #expect(harness.session.projects.isEmpty)
        #expect(harness.session.result == nil)
        #expect(!FileManager.default.fileExists(atPath: harness.store.directory(of: record.id).path))
        #expect(!FileManager.default.fileExists(atPath: exports.path))
    }

    @Test func cancelledRenderReturnsToIdleNotFailed() async throws {
        var deps = Self.dependencies()
        deps.render = { _, _, _, _, _ in throw CancellationError() }
        let harness = try SessionHarness(deps)
        await harness.session.start(sourceURL: try harness.importedSource())
        await harness.session.render(clip: try SessionFixtures.clip())
        #expect(harness.session.renders["f_01_c_01"] == .idle)
        #expect(!harness.session.hasRenderInFlight)
    }

    @Test func resetKeepsTheProjectAndClearsScratch() async throws {
        let harness = try SessionHarness(Self.dependencies())
        await harness.session.start(sourceURL: try harness.importedSource())
        try Data("wav".utf8).write(to: harness.scratch.appending(path: "asr.m4a"))
        harness.session.reset()
        #expect(harness.session.stage == .idle)
        #expect(harness.session.result == nil)
        #expect(harness.session.renders.isEmpty)
        #expect(harness.session.startedAt == nil)
        #expect(harness.session.projects.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: harness.scratch.path).isEmpty)
    }

    @Test func missingAPIKeyFailsBeforeAnyWork() async throws {
        let harness = try SessionHarness(Self.dependencies(transcribeError: SessionTestError.mustNotRun), key: nil)
        let picked = try harness.importedSource()
        await harness.session.start(sourceURL: picked)
        #expect(harness.session.stage == .failed("missingAPIKey"))
        #expect(harness.session.result == nil)
        #expect(harness.session.projects.isEmpty)
        #expect(FileManager.default.fileExists(atPath: picked.path))
    }

    @Test func transcriptionErrorSurfacesVerbatim() async throws {
        let harness = try SessionHarness(Self.dependencies(transcribeError: SessionTestError.speechBroke("no model")))
        await harness.session.start(sourceURL: try harness.importedSource())
        #expect(harness.session.stage == .failed("speechBroke(\"no model\")"))
        // The import survives as an unprocessed project so the user can retry without re-picking.
        #expect(harness.session.projects.count == 1)
        #expect(harness.session.projects.first?.isTranscribed == false)
    }

    @Test func renderErrorIsPerClip() async throws {
        let harness = try SessionHarness(Self.dependencies(renderError: SessionTestError.exportBroke))
        await harness.session.start(sourceURL: try harness.importedSource())
        let clip = try SessionFixtures.clip()
        await harness.session.render(clip: clip)
        #expect(harness.session.renders[clip.id] == .failed("exportBroke"))
        #expect(harness.session.stage == .ready)
    }

    @Test func renderWithoutResultFails() async throws {
        let harness = try SessionHarness(Self.dependencies())
        await harness.session.render(clip: try SessionFixtures.clip())
        #expect(harness.session.renders["f_01_c_01"] == .failed("no slicing result to render"))
    }

    @Test func errorTextKeepsTypedCaseNames() {
        let noop: SessionDependencies.Progress = { _ in }
        noop(1)
        #expect(ErrorText.describe(KeychainError.unexpectedStatus(-34018)) == "unexpectedStatus(-34018)")
        #expect(ErrorText.describe(PhotoLibraryError.accessDenied(.denied)).hasPrefix("accessDenied("))
        #expect(ErrorText.describe(DeepSeekError.missingAPIKey) == "missingAPIKey")
        #expect(ErrorText.describe(SpeechTranscriptionError.noSpeechDetected).contains("人声"))
    }
}

enum SessionTestError: Error, Equatable {
    case mustNotRun
    case speechBroke(String)
    case exportBroke
}
