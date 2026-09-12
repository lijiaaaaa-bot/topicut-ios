import Foundation
import Testing
@testable import LiveSliceCore

struct EDLEditTests {
    @Test func trimShrinksKeptAndClipsRemoved() throws {
        let clip = try TestSupport.clip()
        let trimmed = try EDLEdit.trim(clip, start: 5, end: 20, sourceStart: 1, sourceEnd: 22)
        #expect(trimmed.startSec == 5)
        #expect(trimmed.endSec == 20)
        #expect(trimmed.segments == [TestSupport.segment(5, 13, reason: clip.segments[0].reason), TestSupport.segment(16, 20, reason: clip.segments[1].reason)])
        #expect(trimmed.removedSegments == [TestSupport.segment(13, 16, reason: "答题互动")])
        #expect(trimmed.mode == EDLClip.modeCompressedConcat)
    }

    @Test func trimIntoAGapDropsTheLostKeptSegment() throws {
        let clip = try TestSupport.clip()
        let trimmed = try EDLEdit.trim(clip, start: 14, end: 22, sourceStart: 1, sourceEnd: 22)
        #expect(trimmed.startSec == 16)
        #expect(trimmed.endSec == 22)
        #expect(trimmed.segments.count == 1)
        #expect(trimmed.removedSegments.isEmpty)
        #expect(trimmed.mode == EDLClip.modeContinuous)
    }

    @Test func trimWithNoKeptMediaThrows() throws {
        let clip = try TestSupport.clip()
        #expect(throws: EDLEditError.emptyAfterTrim(clipID: clip.id)) {
            try EDLEdit.trim(clip, start: 13.2, end: 15.5, sourceStart: 1, sourceEnd: 22)
        }
    }

    @Test func trimRejectsNonPositiveAndOutOfRange() throws {
        let clip = try TestSupport.clip()
        #expect(throws: EDLEditError.nonPositiveTrim(clipID: clip.id, start: 10, end: 10)) {
            try EDLEdit.trim(clip, start: 10, end: 10, sourceStart: 1, sourceEnd: 22)
        }
        #expect(throws: EDLEditError.rangeOutsideSource(clipID: clip.id, start: 0, end: 22)) {
            try EDLEdit.trim(clip, start: 0, end: 22, sourceStart: 1, sourceEnd: 22)
        }
    }

    @Test func trimCanExpandEdgeSegments() throws {
        let clip = try TestSupport.clip()
        let expanded = try EDLEdit.trim(clip, start: 0.5, end: 24, sourceStart: 0, sourceEnd: 30)
        #expect(expanded.startSec == 0.5)
        #expect(expanded.endSec == 24)
        #expect(expanded.segments.first?.startSec == 0.5)
        #expect(expanded.segments.last?.endSec == 24)
    }

    @Test func mergeJoinsAGapAsRemoved() throws {
        let first = try TestSupport.clip()
        let second = try trailingClip(start: 25, end: 40)
        let merged = try EDLEdit.merge(first, with: second)
        #expect(merged.id == first.id)
        #expect(merged.title == first.title)
        #expect(merged.segments.map { ($0.startSec, $0.endSec) } == [(1, 13), (16, 22), (25, 40)])
        #expect(merged.removedSegments.contains { $0.startSec == 22 && $0.endSec == 25 })
        #expect(merged.mode == EDLClip.modeCompressedConcat)
    }

    @Test func mergeCoalescesTouchingKeptSegments() throws {
        let first = try TestSupport.clip()
        let second = try trailingClip(start: 22, end: 40)
        let merged = try EDLEdit.merge(first, with: second)
        #expect(merged.segments.map { ($0.startSec, $0.endSec) } == [(1, 13), (16, 40)])
        #expect(merged.removedSegments.map { ($0.startSec, $0.endSec) } == [(13, 16)])
    }

    @Test func discardRemovesTheClipAndSelectsANeighbor() throws {
        let document = try twoClipDocument()
        let (afterFirst, next) = try EDLEdit.discarding(document, clipID: "f_01_c_01")
        #expect(afterFirst.clips.map(\.id) == ["f_01_c_02"])
        #expect(next == "f_01_c_02")
        let (empty, none) = try EDLEdit.discarding(afterFirst, clipID: "f_01_c_02")
        #expect(empty.clips.isEmpty)
        #expect(none == nil)
        #expect(throws: EDLEditError.clipNotFound("missing")) {
            try EDLEdit.discarding(document, clipID: "missing")
        }
    }

    @Test func windowPadsTheClipAndMapsPositions() {
        let window = TrimWindow(clipStart: 72, clipEnd: 108, sourceStart: 0, sourceEnd: 200)
        #expect(window.startSec == 57)
        #expect(window.endSec == 123)
        #expect(window.position(of: 72, width: 100) == 100 * (72 - 57) / (123 - 57))
        #expect(window.time(at: 0, width: 100) == 57)
        #expect(window.time(at: 100, width: 100) == 123)
        #expect(window.ticks(count: 3) == [57, 90, 123])
    }

    @Test func replacingClipsKeepsDocumentMetadata() throws {
        let document = try twoClipDocument()
        let replaced = document.replacingClips([document.clips[1]])
        #expect(replaced.clips.map(\.id) == ["f_01_c_02"])
        #expect(replaced.generatedAt == document.generatedAt)
        #expect(replaced.transcript == document.transcript)
        #expect(replaced.llm == document.llm)
    }

    private func trailingClip(start: Double, end: Double) throws -> EDLClip {
        try EDLClip(
            id: "f_01_c_02", title: "收束", reason: "完整", score: 0.7, tags: ["军事新闻"],
            category: "局势分析", frameworkId: "f_01", frameworkTitle: "框架",
            mode: EDLClip.modeContinuous,
            segments: [TestSupport.segment(start, end)], removedSegments: []
        )
    }

    private func twoClipDocument() throws -> EDLDocument {
        let strategy = SlicingStrategy.topicCompleteGeneral
        return EDLDocument(
            generatedAt: Date(timeIntervalSince1970: 0), strategy: strategy,
            clipCountPolicy: try strategy.clipCountPolicy(forDurationSeconds: 40),
            transcript: EDLTranscriptInfo(cueCount: 3, startSec: 1, endSec: 40),
            clips: [try TestSupport.clip(), try trailingClip(start: 25, end: 40)], llm: nil
        )
    }
}
