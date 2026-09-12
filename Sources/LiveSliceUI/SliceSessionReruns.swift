// Why: things a user can ask for on a finished project — caption/framing look, taste, crop
// focus+zoom, live draft trim, merge, reslice, retranscribe (ADR-0022 / 0024 / 0026).

import CoreGraphics
import Foundation
import LLMKit
import LiveSliceCore
import LiveSliceRender

extension SliceSession {
    public var captionStyle: CaptionStyle {
        get { settings.captionStyle }
        set {
            settings.captionStyle = newValue
            reloadRenders()
        }
    }

    public var captionPosition: CaptionPosition {
        get { settings.captionPosition }
        set {
            settings.captionPosition = newValue
            settings.captionTune = .from(position: newValue)
            reloadRenders()
        }
    }

    public var captionTune: CaptionTune {
        get { settings.captionTune }
        set {
            settings.captionTune = newValue
            reloadRenders()
        }
    }

    public var framingMode: FramingMode {
        get { settings.framingMode }
        set {
            settings.framingMode = newValue
            reloadRenders()
        }
    }

    public var slicingTaste: SlicingTaste {
        get { settings.slicingTaste }
        set { settings.slicingTaste = newValue }
    }

    public var sliceTasteStale: Bool {
        guard let result, let with = result.slicedWith else { return false }
        let key = PipelineReuse.sliceKey(
            model: settings.model, baseURL: settings.baseURL, taste: settings.slicingTaste
        )
        return PipelineReuse.normalizedSliceKey(with) != PipelineReuse.normalizedSliceKey(key)
    }

    public func cropOverride(for clipID: String) -> CropOverride? {
        guard let result else { return nil }
        do {
            return try store.loadCropFocus(of: result.projectID).override(for: clipID)
        } catch {
            stage = .failed(ErrorText.describe(error))
            return nil
        }
    }

    public func cropFocus(for clipID: String) -> CGPoint? { cropOverride(for: clipID)?.focus }

    /// Clip as the stage should play it (saved EDL ± in-memory draft trim).
    public func clipForPreview(_ clip: EDLClip) -> EDLClip {
        guard draftTrimClipID == clip.id else { return clip }
        guard draftTrimLeading > 0 || draftTrimTrailing > 0 else { return clip }
        do {
            return try EDLClipTrim.trimming(clip, leading: draftTrimLeading, trailing: draftTrimTrailing)
        } catch {
            // Invalid draft (too aggressive) — keep the saved clip on stage until the user eases the sliders.
            return clip  // guard-allow: silent-fallback draft-trim-preview-only; Apply path still throws
        }
    }

    public func cropZoom(for clipID: String) -> CGFloat {
        if let zoom = cropOverride(for: clipID)?.zoom { return CGFloat(zoom) }
        return 1
    }

    public func setDraftTrim(clipID: String, leading: Double, trailing: Double) {
        draftTrimClipID = clipID
        draftTrimLeading = leading
        draftTrimTrailing = trailing
    }

    public func clearDraftTrim() {
        draftTrimClipID = nil
        draftTrimLeading = 0
        draftTrimTrailing = 0
    }

    private func invalidateExport(for clipID: String) throws {
        guard let result, let clip = result.document.allClips.first(where: { $0.id == clipID }) else { return }
        renders[clipID] = .idle
        let directory = outputDirectory.appending(path: result.projectID)
        let name = Self.exportName(
            clip: clip, style: settings.captionStyle, position: settings.captionPosition,
            tune: settings.captionTune, framing: settings.framingMode
        )
        let url = directory.appending(path: name)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func setCropFocus(_ point: CGPoint?, for clipID: String) {
        guard let result else { return }
        do {
            var map = try store.loadCropFocus(of: result.projectID)
            map.setFocus(point, for: clipID)
            try store.saveCropFocus(map, of: result.projectID)
            try invalidateExport(for: clipID)
        } catch {
            stage = .failed(ErrorText.describe(error))
        }
    }

    public func setCropZoom(_ zoom: CGFloat, for clipID: String) {
        guard let result else { return }
        do {
            var map = try store.loadCropFocus(of: result.projectID)
            map.setZoom(Double(zoom), for: clipID)
            try store.saveCropFocus(map, of: result.projectID)
            try invalidateExport(for: clipID)
        } catch {
            stage = .failed(ErrorText.describe(error))
        }
    }

    public func clearCropOverride(for clipID: String) {
        guard let result else { return }
        do {
            var map = try store.loadCropFocus(of: result.projectID)
            map.setOverride(nil, for: clipID)
            try store.saveCropFocus(map, of: result.projectID)
            try invalidateExport(for: clipID)
        } catch {
            stage = .failed(ErrorText.describe(error))
        }
    }

    /// Asks the configured AI service to turn a free-text look description into framing/style/tune.
    public func describeLook(_ prompt: String) async throws -> LookDescribeDraft {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LookDescribeError.emptyPrompt }
        let configuration = try settings.deepSeekConfiguration()
        let client = DeepSeekClient(configuration: configuration)
        let result = try await client.chatCompletion(
            messages: [
                ChatMessage(role: "system", content: LookDescribeParser.systemPrompt()),
                ChatMessage(role: "user", content: trimmed),
            ],
            temperature: 0.2,
            responseFormat: .jsonObject
        )
        let (style, framing, tune) = try LookDescribeParser.parse(result.content)
        return LookDescribeDraft(style: style, framing: framing, tune: tune)
    }

    /// Persists the draft trim (or explicit leading/trailing) into the EDL.
    public func trimClip(id: String, leading: Double, trailing: Double) {
        guard let current = result else { return }
        do {
            guard let original = current.document.allClips.first(where: { $0.id == id }) else { return }
            let trimmed = try EDLClipTrim.trimming(original, leading: leading, trailing: trailing)
            try replaceDocumentClip(trimmed, in: current)
            clearDraftTrim()
        } catch {
            stage = .failed(ErrorText.describe(error))
        }
    }

    /// Merges `id` with the next clip in the same list (topics or highlights); drops the absorbed id.
    public func mergeWithNext(id: String) {
        guard let current = result else { return }
        do {
            let document = current.document
            if let i = document.clips.firstIndex(where: { $0.id == id }), i + 1 < document.clips.count {
                let absorbed = document.clips[i + 1].id
                let merged = try EDLClipMerge.merging(document.clips[i], document.clips[i + 1])
                var clips = document.clips
                clips.remove(at: i + 1)
                clips[i] = merged
                let next = document.replacingAllClips(clips, highlights: document.highlights)
                try saveDocument(next, from: current)
                renders[absorbed] = nil
                renders[id] = .idle
                return
            }
            if var highlights = document.highlights,
               let i = highlights.firstIndex(where: { $0.id == id }), i + 1 < highlights.count {
                let absorbed = highlights[i + 1].id
                let merged = try EDLClipMerge.merging(highlights[i], highlights[i + 1])
                highlights.remove(at: i + 1)
                highlights[i] = merged
                let next = document.replacingAllClips(document.clips, highlights: highlights)
                try saveDocument(next, from: current)
                renders[absorbed] = nil
                renders[id] = .idle
                return
            }
        } catch {
            stage = .failed(ErrorText.describe(error))
        }
    }

    private func replaceDocumentClip(_ clip: EDLClip, in current: SessionResult) throws {
        let document = try current.document.replacingClip(clip)
        try saveDocument(document, from: current)
        renders[clip.id] = .idle
    }

    private func saveDocument(_ document: EDLDocument, from current: SessionResult) throws {
        var record = try store.load(id: current.projectID)
        record.document = document
        try store.save(record)
        refreshProjects()
        result = SessionResult(
            projectID: current.projectID, sourceURL: current.sourceURL, cues: current.cues,
            document: document, localeIdentifier: current.localeIdentifier,
            slicedWith: current.slicedWith, words: current.words
        )
    }

    /// Re-slice from the workbench studio: discard EDL, then run the paid call with current taste.
    /// Does not stop at `.awaitingSlice` — the user already confirmed in the sheet.
    public func resliceFromTaste() async {
        guard let current = result else {
            stage = .failed("no project on screen to slice again")
            return
        }
        do {
            var record = try store.load(id: current.projectID)
            try discardSlice(of: &record)
            try store.save(record)
            refreshProjects()
            awaitingSlice = AwaitingSliceInfo(
                projectID: current.projectID, sourceURL: current.sourceURL, cueCount: current.cues.count,
                localeIdentifier: current.localeIdentifier, hasWords: current.words != nil
            )
            result = nil
            renders = [:]
            await confirmSlice()
        } catch {
            stage = .failed(ErrorText.describe(error))
        }
    }

    public func reslice() async {
        guard let current = result else {
            stage = .failed("no project on screen to slice again")
            return
        }
        beginRun()
        do {
            var record = try store.load(id: current.projectID)
            try discardSlice(of: &record)
            try store.save(record)
            refreshProjects()
            await run(record)
        } catch {
            stage = .failed(ErrorText.describe(error))
        }
    }

    public func retranscribe() async {
        guard let current = result else {
            stage = .failed("no project on screen to transcribe again")
            return
        }
        beginRun()
        do {
            var record = try store.load(id: current.projectID)
            let sourceURL = try store.requireSource(of: record)
            try await transcribeStep(&record, sourceURL: sourceURL, preference: settings.localePreference)
            await run(record)
        } catch {
            stage = .failed(ErrorText.describe(error))
        }
    }

    public func reloadRenders() {
        guard let result else { return }
        do {
            let onDisk = try restoredRenders(projectID: result.projectID, clips: result.document.allClips)
            let inFlight = renders.filter { if case .rendering = $0.value { return true } else { return false } }
            renders = onDisk.merging(inFlight) { _, running in running }
        } catch {
            stage = .failed(ErrorText.describe(error))
        }
    }
}
