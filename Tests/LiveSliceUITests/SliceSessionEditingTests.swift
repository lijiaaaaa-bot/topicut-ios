import Foundation
import Testing
@testable import LiveSliceUI
import LiveSliceCore

@MainActor
struct SliceSessionEditingTests {
    @Test func applyEditedDocumentPersistsWithoutReslicingAndClearsTouchedExports() async throws {
        let harness = try SessionHarness(SliceSessionTests.dependencies(
            transcribeError: SessionTestError.mustNotRun, sliceError: SessionTestError.mustNotRun
        ), key: nil)
        let document = try SessionFixtures.document()
        let sliceKey = PipelineReuse.sliceKey(model: harness.settings.model, baseURL: harness.settings.baseURL)
        let record = try harness.savedProject(
            srt: try SRTWriter.serialize(SessionFixtures.cues), document: document,
            slicedWith: sliceKey
        )
        let file = try Self.writeExport(harness: harness, projectID: record.id, clipID: "f_01_c_01")
        await harness.session.open(record)
        #expect(harness.session.stage == .ready)
        try Self.expectDone(harness.session.renders["f_01_c_01"], matching: file)

        let trimmed = try EDLEdit.trim(
            try SessionFixtures.clip(), start: 5, end: 20, sourceStart: 1, sourceEnd: 22
        )
        try harness.session.applyEditedDocument(document.replacingClips([trimmed]), clearingExportIDs: [trimmed.id])
        #expect(harness.session.stage == .ready)
        #expect(harness.session.result?.document.clips.first?.startSec == 5)
        #expect(harness.session.result?.document.clips.first?.endSec == 20)
        #expect(harness.session.result?.slicedWith == sliceKey)
        #expect(harness.session.renders["f_01_c_01"] == .idle)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try harness.store.load(id: record.id).document?.clips.first?.startSec == 5)
    }

    @Test func applyEditedDocumentWithoutResultThrows() throws {
        let harness = try SessionHarness(SliceSessionTests.dependencies())
        #expect(throws: SliceSessionError.noResultToEdit) {
            try harness.session.applyEditedDocument(try SessionFixtures.document(), clearingExportIDs: [])
        }
    }

    @Test func applyEditedDocumentDropsDiscardedRenderState() async throws {
        let document = try Self.twoClipDocument()
        let harness = try SessionHarness(SliceSessionTests.dependencies())
        let record = try harness.savedProject(
            srt: try SRTWriter.serialize(SessionFixtures.cues), document: document
        )
        _ = try Self.writeExport(harness: harness, projectID: record.id, clipID: "f_01_c_01")
        let kept = try Self.writeExport(harness: harness, projectID: record.id, clipID: "f_01_c_02")
        await harness.session.open(record)

        try harness.session.applyEditedDocument(
            document.replacingClips([document.clips[1]]), clearingExportIDs: [document.clips[0].id]
        )
        #expect(harness.session.result?.document.clips.map(\.id) == ["f_01_c_02"])
        #expect(harness.session.renders["f_01_c_01"] == nil)
        #expect(harness.session.renders["f_01_c_02"] != nil)
        #expect(!FileManager.default.fileExists(atPath: kept.deletingLastPathComponent().appending(path: "f_01_c_01.mp4").path))
        #expect(FileManager.default.fileExists(atPath: kept.path))
    }

    private static func writeExport(harness: SessionHarness, projectID: String, clipID: String) throws -> URL {
        let directory = harness.output.appending(path: projectID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "\(clipID).mp4")
        try Data(clipID.utf8).write(to: file)
        return file
    }

    private static func expectDone(_ state: ClipRenderState?, matching file: URL) throws {
        guard case .done(let url) = state else {
            Issue.record("expected .done, got \(String(describing: state))")
            return
        }
        #expect(url.resolvingSymlinksInPath() == file.resolvingSymlinksInPath())
    }

    private static func twoClipDocument() throws -> EDLDocument {
        let second = try EDLClip(
            id: "f_01_c_02", title: "收束", reason: "完整", score: 0.7, tags: [], category: nil,
            frameworkId: "f_01", frameworkTitle: "框架", mode: EDLClip.modeContinuous,
            segments: [EDLSegment(startSec: 25, endSec: 40, reason: nil)], removedSegments: []
        )
        return EDLDocument(
            generatedAt: Date(timeIntervalSince1970: 0), strategy: .topicCompleteGeneral,
            clipCountPolicy: try SlicingStrategy.topicCompleteGeneral.clipCountPolicy(forDurationSeconds: 40),
            transcript: EDLTranscriptInfo(cueCount: 3, startSec: 1, endSec: 40),
            clips: [try SessionFixtures.clip(), second], llm: nil
        )
    }
}
