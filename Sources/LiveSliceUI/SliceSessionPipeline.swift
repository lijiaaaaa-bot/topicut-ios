// Why: the ASR → awaitingSlice → confirmSlice path (ADR-0028) lives beside the session type so
// SliceSession.swift stays under the god-object line limit.

import Foundation
import LiveSliceASR
import LiveSliceCore
import LiveSliceRender

extension SliceSession {
    /// The pipeline from wherever `record` stopped. A saved step is reused only while the inputs
    /// that produced it are unchanged (`PipelineReuse`); a changed input reruns that step and every
    /// step after it. Each finished step is saved before the next begins.
    /// After ASR, if there is no current EDL, stops at `.awaitingSlice` until `confirmSlice()` (ADR-0028).
    func run(_ initial: ProjectRecord) async {
        var record = initial
        do {
            let sourceURL = try store.requireSource(of: record)
            let preference = settings.localePreference
            let sliceKey = PipelineReuse.sliceKey(
                model: settings.model, baseURL: settings.baseURL, taste: settings.slicingTaste
            )
            let transcriptCurrent = PipelineReuse.transcriptIsCurrent(record, preference: preference)
            if !transcriptCurrent {
                try discardSlice(of: &record)
                try await transcribeStep(&record, sourceURL: sourceURL, preference: preference)
            }
            guard let srt = record.srt, let localeIdentifier = record.localeIdentifier else {
                throw ProjectStoreError.corruptRecord(record.id)
            }
            activeLocaleIdentifier = localeIdentifier
            if PipelineReuse.sliceIsCurrent(record, transcriptCurrent: transcriptCurrent, key: sliceKey),
               let stored = record.document {
                try finishReady(
                    record: record, sourceURL: sourceURL, srt: srt, localeIdentifier: localeIdentifier, document: stored
                )
                return
            }
            try discardSlice(of: &record)
            let cues = try SRTParser.parse(srt)
            let words = try store.loadWords(of: record.id)
            awaitingSlice = AwaitingSliceInfo(
                projectID: record.id, sourceURL: sourceURL, cueCount: cues.count,
                localeIdentifier: localeIdentifier, hasWords: words != nil
            )
            stage = .awaitingSlice
        } catch {
            awaitingSlice = nil
            stage = .failed(ErrorText.describe(error))
        }
    }

    /// Paid AI slice using the current taste. Only valid from `.awaitingSlice`.
    public func confirmSlice() async {
        guard let awaiting = awaitingSlice else {
            stage = .failed("no transcript waiting to slice")
            return
        }
        sliceError = nil
        startedAt = Date()
        do {
            var record = try store.load(id: awaiting.projectID)
            guard let srt = record.srt else { throw ProjectStoreError.corruptRecord(record.id) }
            let configuration = try settings.deepSeekConfiguration()
            let sliceKey = PipelineReuse.sliceKey(
                model: settings.model, baseURL: settings.baseURL, taste: settings.slicingTaste
            )
            slicingService = settings.servicePreset?.name ?? configuration.baseURL.host() ?? settings.baseURL
            stage = .slicing
            record.document = try await dependencies.slice(srt, configuration, settings.slicingTaste)
            record.slicedWith = sliceKey
            try store.save(record)
            refreshProjects()
            guard let document = record.document else { throw ProjectStoreError.corruptRecord(record.id) }
            try finishReady(
                record: record, sourceURL: awaiting.sourceURL, srt: srt,
                localeIdentifier: awaiting.localeIdentifier, document: document
            )
        } catch {
            sliceError = ErrorText.describe(error)
            stage = .awaitingSlice
        }
    }

    func finishReady(
        record: ProjectRecord, sourceURL: URL, srt: String, localeIdentifier: String, document raw: EDLDocument
    ) throws {
        let document = try raw.withUniqueClipIDs()
        var record = record
        if document != raw {
            record.document = document
            try store.save(record)
            refreshProjects()
        }
        result = SessionResult(
            projectID: record.id, sourceURL: sourceURL, cues: try SRTParser.parse(srt),
            document: document, localeIdentifier: localeIdentifier, slicedWith: record.slicedWith,
            words: try store.loadWords(of: record.id)
        )
        renders = try restoredRenders(projectID: record.id, clips: document.allClips)
        awaitingSlice = nil
        sliceError = nil
        stage = .ready
    }

    /// Speech recognition for `record`: model, transcript, words — each saved before the next step.
    /// Old words go first so a failure here never leaves last run's words next to a new transcript.
    func transcribeStep(_ record: inout ProjectRecord, sourceURL: URL, preference: ASRLocalePreference) async throws {
        try store.deleteWords(of: record.id)
        stage = .preparingModel(0)
        try await dependencies.prepareModel(preference) { [weak self] value in
            Task { @MainActor in self?.stage = .preparingModel(value) }
        }
        stage = .transcribing(0)
        let outcome = try await dependencies.transcribe(sourceURL, preference, scratchDirectory) { [weak self] value in
            Task { @MainActor in self?.stage = .transcribing(value) }
        }
        record.srt = try SRTWriter.serialize(outcome.cues)
        record.localeIdentifier = outcome.locale.identifier
        record.transcribedWith = preference.identifier
        try store.saveWords(outcome.words, of: record.id)
        try store.save(record)
        refreshProjects()
    }
}
