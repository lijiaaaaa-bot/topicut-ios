// Why: the workbench sheet holds one in-progress EDL rewrite. Trim always applies against
// the clip as it was at the last structural edit so expanding a handle can restore a cut;
// discard and merge update the selection the sheet is sitting on.

import Foundation

/// In-memory EDL rewrite for one sheet session. Persist through `SliceSession`; this type
/// does not touch disk, exports, ASR, or DeepSeek.
public struct EDLEditor: Equatable, Sendable {
    public private(set) var document: EDLDocument
    public private(set) var clipID: String?
    public private(set) var touchedIDs: Set<String>
    private var bases: [String: EDLClip]

    public init(document: EDLDocument, clipID: String) throws {
        guard document.clips.contains(where: { $0.id == clipID }) else {
            throw EDLEditError.clipNotFound(clipID)
        }
        self.document = document
        self.clipID = clipID
        self.touchedIDs = []
        var bases: [String: EDLClip] = [:]
        for clip in document.clips { bases[clip.id] = clip }
        self.bases = bases
    }

    public var currentClip: EDLClip? {
        guard let clipID else { return nil }
        return document.clips.first(where: { $0.id == clipID })
    }

    public var sourceStart: Double {
        times.min() ?? document.transcript.startSec
    }

    public var sourceEnd: Double {
        times.max() ?? document.transcript.endSec
    }

    public var trimWindow: TrimWindow {
        let base = clipID.flatMap { bases[$0] } ?? currentClip
        return TrimWindow(
            clipStart: base?.startSec ?? sourceStart,
            clipEnd: base?.endSec ?? sourceEnd,
            sourceStart: sourceStart,
            sourceEnd: sourceEnd
        )
    }

    public var canMergeWithNext: Bool {
        guard let pair = nextPair() else { return false }
        do {
            _ = try EDLEdit.merge(pair.current, with: pair.next)
            return true
        } catch {
            return false
        }
    }

    public mutating func trim(start: Double, end: Double) throws {
        guard let clipID, let current = currentClip else { throw EDLEditError.noCurrentClip }
        let base = bases[clipID] ?? current
        let trimmed = try EDLEdit.trim(
            base, start: start, end: end, sourceStart: sourceStart, sourceEnd: sourceEnd
        )
        try replaceCurrent(trimmed)
        touchedIDs.insert(clipID)
    }

    public mutating func discardCurrent() throws {
        guard let clipID else { throw EDLEditError.noCurrentClip }
        let (nextDocument, nextID) = try EDLEdit.discarding(document, clipID: clipID)
        touchedIDs.insert(clipID)
        bases[clipID] = nil
        document = nextDocument
        self.clipID = nextID
    }

    public mutating func mergeWithNext() throws {
        guard let pair = nextPair() else { throw EDLEditError.noNextClip }
        let merged = try EDLEdit.merge(pair.current, with: pair.next)
        var clips = document.clips
        guard let index = clips.firstIndex(where: { $0.id == pair.current.id }) else {
            throw EDLEditError.clipNotFound(pair.current.id)
        }
        clips[index] = merged
        clips.remove(at: index + 1)
        document = document.replacingClips(clips)
        touchedIDs.insert(merged.id)
        touchedIDs.insert(pair.next.id)
        bases[merged.id] = merged
        bases[pair.next.id] = nil
        clipID = merged.id
    }

    private var times: [Double] {
        [document.transcript.startSec, document.transcript.endSec]
            + document.clips.flatMap { [$0.startSec, $0.endSec] }
            + bases.values.flatMap { [$0.startSec, $0.endSec] }
    }

    private func nextPair() -> (current: EDLClip, next: EDLClip)? {
        guard let clipID, let index = document.clips.firstIndex(where: { $0.id == clipID }) else {
            return nil
        }
        let next = index + 1
        guard next < document.clips.count else { return nil }
        return (document.clips[index], document.clips[next])
    }

    private mutating func replaceCurrent(_ clip: EDLClip) throws {
        var clips = document.clips
        guard let index = clips.firstIndex(where: { $0.id == clip.id }) else {
            throw EDLEditError.clipNotFound(clip.id)
        }
        clips[index] = clip
        document = document.replacingClips(clips)
    }
}
