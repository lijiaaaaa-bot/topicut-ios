import Foundation
import Testing
@testable import LiveSliceCore

struct EDLEditorTests {
    @Test func trimAppliesAgainstTheBaseSoExpandRestoresCuts() throws {
        var editor = try EDLEditor(document: try document(), clipID: "f_01_c_01")
        try editor.trim(start: 16, end: 22)
        #expect(editor.currentClip?.segments.count == 1)
        #expect(editor.touchedIDs == ["f_01_c_01"])
        try editor.trim(start: 1, end: 22)
        #expect(editor.currentClip?.segments.count == 2)
        #expect(editor.currentClip?.removedSegments.count == 1)
    }

    @Test func mergeWithNextHidesOnTheLastClip() throws {
        var editor = try EDLEditor(document: try document(), clipID: "f_01_c_01")
        #expect(editor.canMergeWithNext)
        try editor.mergeWithNext()
        #expect(editor.document.clips.count == 1)
        #expect(editor.clipID == "f_01_c_01")
        #expect(editor.currentClip?.endSec == 40)
        #expect(editor.touchedIDs.contains("f_01_c_01"))
        #expect(editor.touchedIDs.contains("f_01_c_02"))
        #expect(!editor.canMergeWithNext)
        #expect(throws: EDLEditError.noNextClip) { try editor.mergeWithNext() }
    }

    @Test func discardSelectsTheNeighborAndClearsTheLastClip() throws {
        var editor = try EDLEditor(document: try document(), clipID: "f_01_c_01")
        try editor.discardCurrent()
        #expect(editor.clipID == "f_01_c_02")
        #expect(editor.document.clips.map(\.id) == ["f_01_c_02"])
        try editor.discardCurrent()
        #expect(editor.clipID == nil)
        #expect(editor.document.clips.isEmpty)
        #expect(!editor.canMergeWithNext)
        #expect(throws: EDLEditError.noCurrentClip) { try editor.discardCurrent() }
    }

    @Test func unknownClipIDFailsAtInit() {
        #expect(throws: EDLEditError.clipNotFound("missing")) {
            try EDLEditor(document: try document(), clipID: "missing")
        }
    }

    @Test func windowFollowsTheUntrimmedBase() throws {
        var editor = try EDLEditor(document: try document(), clipID: "f_01_c_01")
        let before = editor.trimWindow
        try editor.trim(start: 16, end: 22)
        #expect(editor.trimWindow == before)
    }

    private func document() throws -> EDLDocument {
        let strategy = SlicingStrategy.topicCompleteGeneral
        let second = try EDLClip(
            id: "f_01_c_02", title: "收束", reason: "完整", score: 0.7, tags: [],
            category: nil, frameworkId: "f_01", frameworkTitle: "框架",
            mode: EDLClip.modeContinuous,
            segments: [TestSupport.segment(25, 40)], removedSegments: []
        )
        return EDLDocument(
            generatedAt: Date(timeIntervalSince1970: 0), strategy: strategy,
            clipCountPolicy: try strategy.clipCountPolicy(forDurationSeconds: 40),
            transcript: EDLTranscriptInfo(cueCount: 3, startSec: 1, endSec: 40),
            clips: [try TestSupport.clip(), second], llm: nil
        )
    }
}
