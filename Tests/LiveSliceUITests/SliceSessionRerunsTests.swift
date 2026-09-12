import Foundation
import Testing
@testable import LiveSliceUI
import LiveSliceCore

/// ADR-0024: timed words travel with the transcript; exports are named by caption style; a project
/// without words can be transcribed again without touching its EDL. (`reslice` is covered next to
/// the reuse rules in SliceSessionReuseTests.)
@MainActor
struct SliceSessionRerunsTests {
    // ADR-0024: words travel with the transcript; the export name carries the caption style.
    @Test func wordsAreSavedWithTheTranscriptAndReachTheResult() async throws {
        let harness = try SessionHarness(SliceSessionTests.dependencies())
        try await harness.startThroughSlice()
        let result = try #require(harness.session.result)
        #expect(result.words == SessionFixtures.words)
        #expect(try harness.store.loadWords(of: result.projectID) == SessionFixtures.words)

        // Reopen: the words come back from disk, not from a rerun.
        await harness.session.open(try #require(harness.session.projects.first))
        #expect(harness.session.result?.words == SessionFixtures.words)
    }

    @Test func projectTranscribedBeforeWordsWereKeptHasNilWords() async throws {
        let harness = try SessionHarness(SliceSessionTests.dependencies())
        let record = try harness.savedProject(
            srt: try SRTWriter.serialize(SessionFixtures.cues), document: try SessionFixtures.document(),
            transcribedWith: "auto", slicedWith: PipelineReuse.sliceKey(model: harness.settings.model, baseURL: harness.settings.baseURL)
        )
        await harness.session.open(record)
        #expect(harness.session.stage == .ready)
        #expect(harness.session.result?.words == nil)
    }

    @Test func exportNameFollowsTheCaptionStyleAndReloadFindsEachStylesFiles() async throws {
        var deps = SliceSessionTests.dependencies()
        deps.render = { _, _, _, words, style, _, _, _, _, _, output, _ in
            #expect(words == SessionFixtures.words)
            try Data(style.rawValue.utf8).write(to: output)
            return output
        }
        let harness = try SessionHarness(deps)
        try await harness.startThroughSlice()
        let clip = try SessionFixtures.clip()

        await harness.session.render(clip: clip)
        guard case .done(let clean) = harness.session.renders[clip.id] else { Issue.record("clean export missing"); return }
        #expect(clean.lastPathComponent == "f_01_c_01.mp4")

        harness.settings.captionStyle = .highlightWord
        harness.session.reloadRenders()
        #expect(harness.session.renders[clip.id] == nil, "a clean export is not a word-highlight export")
        await harness.session.render(clip: clip)
        guard case .done(let words) = harness.session.renders[clip.id] else { Issue.record("word export missing"); return }
        #expect(words.lastPathComponent == "f_01_c_01-words.mp4")
        #expect(try String(contentsOf: words, encoding: .utf8) == "highlightWord")

        harness.settings.captionStyle = .none
        harness.session.reloadRenders()
        #expect(harness.session.renders[clip.id] == nil)
        harness.settings.captionStyle = .clean
        harness.session.reloadRenders()
        guard case .done(let again) = harness.session.renders[clip.id] else { Issue.record("clean export not found again"); return }
        #expect(again.lastPathComponent == "f_01_c_01.mp4")
    }

    @Test func settingTheStyleOnTheSessionPersistsItAndReloadsTheRenders() async throws {
        let harness = try SessionHarness(SliceSessionTests.dependencies())
        try await harness.startThroughSlice()
        let clip = try SessionFixtures.clip()
        await harness.session.render(clip: clip)
        #expect(harness.session.renders[clip.id] != nil)

        harness.session.captionStyle = .none
        #expect(harness.settings.captionStyle == .none)
        #expect(harness.session.renders[clip.id] == nil, "the clean export does not count for the no-caption style")
        harness.session.captionStyle = .clean
        #expect(harness.session.renders[clip.id] != nil)
    }

    // ADR-0024: `retranscribe` reruns speech recognition only; the EDL, its exports and the AI bill stay untouched.
    @Test func retranscribeAddsWordsAndKeepsTheEDLAndExports() async throws {
        let calls = StepCalls()
        let harness = try SessionHarness(SliceSessionReuseTests.counting(calls))
        let record = try harness.savedProject(
            srt: try SRTWriter.serialize(SessionFixtures.cues), document: try SessionFixtures.document(),
            transcribedWith: "auto", slicedWith: SliceSessionReuseTests.currentKey
        )
        let export = harness.output.appending(path: record.id).appending(path: "f_01_c_01.mp4")
        try FileManager.default.createDirectory(at: export.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: export)
        await harness.session.open(record)
        #expect(harness.session.result?.words == nil)

        await harness.session.retranscribe()
        #expect(harness.session.stage == .ready)
        #expect(await calls.transcribe == 1)
        #expect(await calls.slice == 0, "the EDL is bound to the video, not to the transcript text")
        #expect(harness.session.result?.words == SessionFixtures.words)
        #expect(try harness.store.loadWords(of: record.id) == SessionFixtures.words)
        #expect(harness.session.result?.document == record.document)
        #expect(harness.session.renders["f_01_c_01"] != nil, "exports survive")
        #expect(try harness.store.load(id: record.id).transcribedWith == "auto")
    }

    @Test func retranscribeWithNothingOnScreenIsAFailureNotASilentNoop() async throws {
        let harness = try SessionHarness(SliceSessionTests.dependencies())
        await harness.session.retranscribe()
        #expect(harness.session.stage == .failed("no project on screen to transcribe again"))
    }

    @Test func retranscribeFailureIsShownAndTheOldWordsAreGone() async throws {
        let harness = try SessionHarness(SliceSessionTests.dependencies(transcribeError: SessionTestError.speechBroke("asr")))
        let record = try harness.savedProject(
            srt: try SRTWriter.serialize(SessionFixtures.cues), document: try SessionFixtures.document(),
            transcribedWith: "auto", slicedWith: SliceSessionReuseTests.currentKey
        )
        try harness.store.saveWords(SessionFixtures.words, of: record.id)
        await harness.session.open(record)
        #expect(harness.session.stage == .ready)

        await harness.session.retranscribe()
        guard case .failed(let message) = harness.session.stage else { Issue.record("expected failure, got \(harness.session.stage)"); return }
        #expect(message.contains("speechBroke"))
        #expect(try harness.store.loadWords(of: record.id) == nil, "stale words never sit next to a failed run")
        #expect(try harness.store.load(id: record.id).document != nil, "the EDL is not the failed step")
    }

    // ADR-0026: draft trim changes what the stage plays before the EDL is saved.
    @Test func draftTrimChangesClipForPreviewWithoutWritingTheEDL() async throws {
        let harness = try SessionHarness(SliceSessionTests.dependencies())
        try await harness.startThroughSlice()
        let clip = try #require(harness.session.result?.document.clips.first)
        let before = clip.endSec - clip.startSec
        harness.session.setDraftTrim(clipID: clip.id, leading: 2, trailing: 1)
        let draft = harness.session.clipForPreview(clip)
        #expect(draft.startSec == clip.startSec + 2)
        #expect(draft.endSec == clip.endSec - 1)
        #expect(draft.endSec - draft.startSec < before)
        #expect(harness.session.result?.document.clips.first?.startSec == clip.startSec, "EDL untouched until apply")
        harness.session.trimClip(id: clip.id, leading: 2, trailing: 1)
        let saved = try #require(harness.session.result?.document.clips.first)
        #expect(saved.startSec == clip.startSec + 2)
        #expect(harness.session.draftTrimClipID == nil)
    }

    @Test func mergeWithNextJoinsAdjacentClipsAndDropsTheAbsorbedID() async throws {
        let a = try EDLClip(
            id: "f_01_c_01", title: "甲", reason: "a", score: 0.8, tags: [], category: nil,
            frameworkId: "f_01", frameworkTitle: "框", mode: EDLClip.modeContinuous,
            segments: [EDLSegment(startSec: 1, endSec: 5, reason: nil)], removedSegments: []
        )
        let b = try EDLClip(
            id: "f_01_c_02", title: "乙", reason: "b", score: 0.6, tags: [], category: nil,
            frameworkId: "f_01", frameworkTitle: "框", mode: EDLClip.modeContinuous,
            segments: [EDLSegment(startSec: 8, endSec: 12, reason: nil)], removedSegments: []
        )
        let strategy = SlicingStrategy.topicCompleteGeneral
        let document = EDLDocument(
            generatedAt: Date(timeIntervalSince1970: 0), strategy: strategy,
            clipCountPolicy: try strategy.clipCountPolicy(forDurationSeconds: 12),
            transcript: EDLTranscriptInfo(cueCount: 2, startSec: 1, endSec: 12),
            clips: [a, b], llm: nil
        )
        let harness = try SessionHarness(SliceSessionTests.dependencies())
        let record = try harness.savedProject(
            srt: try SRTWriter.serialize(SessionFixtures.cues), document: document,
            transcribedWith: "auto", slicedWith: SliceSessionReuseTests.currentKey
        )
        await harness.session.open(record)
        harness.session.mergeWithNext(id: a.id)
        let clips = try #require(harness.session.result?.document.clips)
        #expect(clips.count == 1)
        #expect(clips[0].id == a.id)
        #expect(clips[0].segments.count == 2)
        #expect(clips[0].endSec == 12)
        #expect(harness.session.renders[b.id] == nil)
    }
}
