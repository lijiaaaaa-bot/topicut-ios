// Why: the app's one workflow — video in, transcribed on device, sliced by DeepSeek, rendered to
// MP4s — as an observable state machine. Every failure lands in `.failed(message)` with the real
// error text; there is no partial "success" state. A cancelled render goes back to `.idle` because
// nothing was produced. Dependencies are plain functions so tests drive the state machine without
// speech, network, or export. Each import becomes a ProjectRecord checkpointed after transcription
// and after slicing, so `open` resumes at the first unfinished step and a sliced project is ready
// at once. Only the scratch directory (extracted audio) is purged at `start`/`reset`.

import Foundation
import LiveSliceASR
import LiveSliceCore
import Observation

@MainActor
@Observable
public final class SliceSession {
    public private(set) var stage: SessionStage = .idle
    public private(set) var result: SessionResult?
    public private(set) var renders: [String: ClipRenderState] = [:]
    /// When the current pipeline run began; drives the elapsed-time readout, never an estimate.
    public private(set) var startedAt: Date?
    /// Locale actually used for the current/last transcription (after automatic detection).
    public private(set) var activeLocaleIdentifier: String?
    /// Saved projects, newest first; refreshed after every store change.
    public private(set) var projects: [ProjectRecord] = []

    private let dependencies: SessionDependencies
    private let settings: AppSettings
    private let store: ProjectStore
    private let scratchDirectory: URL
    private let outputDirectory: URL

    public init(
        settings: AppSettings, dependencies: SessionDependencies, store: ProjectStore,
        scratchDirectory: URL, outputDirectory: URL
    ) {
        self.settings = settings
        self.dependencies = dependencies
        self.store = store
        self.scratchDirectory = scratchDirectory
        self.outputDirectory = outputDirectory
        refreshProjects()
    }

    public func sourceURL(of record: ProjectRecord) -> URL { store.sourceURL(of: record) }

    /// Re-reads the project list; an unreadable store is shown, not hidden behind an empty list.
    public func refreshProjects() {
        do {
            projects = try store.list()
        } catch {
            stage = .failed(ErrorText.describe(error))
        }
    }

    public var isBusy: Bool {
        switch stage {
        case .preparingModel, .transcribing, .slicing: return true
        case .idle, .ready, .failed: return false
        }
    }

    public var hasRenderInFlight: Bool {
        renders.values.contains { if case .rendering = $0 { return true } else { return false } }
    }

    /// True while the pipeline or any export is running — the app must stay awake for it.
    public var isWorking: Bool { isBusy || hasRenderInFlight }

    /// Imports a freshly picked file and runs the pipeline on it. A file whose fingerprint matches
    /// a saved project is that project: the duplicate copy is discarded and the project reopened,
    /// so nothing already computed for this video runs again. Requires a stored API key first.
    public func start(sourceURL: URL) async {
        beginRun()
        do {
            _ = try settings.deepSeekConfiguration()
            let fingerprint = try await Task.detached { try SourceFingerprint.compute(url: sourceURL) }.value
            if let existing = projects.first(where: { $0.sourceFingerprint == fingerprint }) {
                try FileManager.default.removeItem(at: sourceURL)
                try purgeScratch()
                await run(existing)
                return
            }
            let record = try store.adopt(sourceURL: sourceURL, fingerprint: fingerprint)
            refreshProjects()
            try purgeScratch()
            await run(record)
        } catch {
            stage = .failed(ErrorText.describe(error))
        }
    }

    /// Reopens a saved project: ready at once when sliced, otherwise resumes at the first
    /// unfinished step (a transcribed project skips speech recognition entirely).
    public func open(_ record: ProjectRecord) async {
        beginRun()
        do {
            try purgeScratch()
            await run(record)
        } catch {
            stage = .failed(ErrorText.describe(error))
        }
    }

    /// Removes a project, its source video and its exports. The current result is kept if it
    /// belongs to another project.
    public func delete(_ record: ProjectRecord) {
        do {
            try store.delete(id: record.id)
            let exports = outputDirectory.appending(path: record.id)
            if FileManager.default.fileExists(atPath: exports.path) { try FileManager.default.removeItem(at: exports) }
            if result?.projectID == record.id { result = nil; renders = [:] }
            refreshProjects()
        } catch {
            stage = .failed(ErrorText.describe(error))
        }
    }

    private func beginRun() {
        result = nil
        renders = [:]
        activeLocaleIdentifier = nil
        startedAt = Date()
    }

    /// The pipeline from wherever `record` stopped. A saved step is reused only while the inputs
    /// that produced it are unchanged (`PipelineReuse`); a changed input reruns that step and every
    /// step after it. Each finished step is saved before the next begins.
    private func run(_ initial: ProjectRecord) async {
        var record = initial
        do {
            let sourceURL = try store.requireSource(of: record)
            let preference = settings.localePreference
            let sliceKey = PipelineReuse.sliceKey(model: settings.model, baseURL: settings.baseURL)
            let transcriptCurrent = PipelineReuse.transcriptIsCurrent(record, preference: preference)
            if !transcriptCurrent {
                try discardSlice(of: &record) // a transcript in another language invalidates the EDL too
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
                try store.save(record)
                refreshProjects()
            }
            guard let srt = record.srt, let localeIdentifier = record.localeIdentifier else {
                throw ProjectStoreError.corruptRecord(record.id)
            }
            activeLocaleIdentifier = localeIdentifier
            if !PipelineReuse.sliceIsCurrent(record, transcriptCurrent: transcriptCurrent, key: sliceKey) {
                try discardSlice(of: &record)
                let configuration = try settings.deepSeekConfiguration()
                stage = .slicing
                record.document = try await dependencies.slice(srt, configuration)
                record.slicedWith = sliceKey
                try store.save(record)
                refreshProjects()
            }
            guard let stored = record.document else { throw ProjectStoreError.corruptRecord(record.id) }
            // Documents saved before the unique-id rule may carry duplicate clip ids; relabel once.
            let document = try stored.withUniqueClipIDs()
            if document != stored {
                record.document = document
                try store.save(record)
                refreshProjects()
            }
            result = SessionResult(
                projectID: record.id, sourceURL: sourceURL, cues: try SRTParser.parse(srt),
                document: document, localeIdentifier: localeIdentifier, slicedWith: record.slicedWith
            )
            renders = try restoredRenders(projectID: record.id, clips: document.clips)
            stage = .ready
        } catch {
            stage = .failed(ErrorText.describe(error))
        }
    }

    /// Drops a stale EDL and the exports cut from it: a new slicing run reuses clip ids, so an old
    /// `<clipID>.mp4` would otherwise pass for the new clip's export.
    private func discardSlice(of record: inout ProjectRecord) throws {
        guard record.document != nil else { return }
        record.document = nil
        record.slicedWith = nil
        let exports = outputDirectory.appending(path: record.id)
        if FileManager.default.fileExists(atPath: exports.path) { try FileManager.default.removeItem(at: exports) }
    }

    /// Exports already on disk for this project, keyed back to their clip.
    private func restoredRenders(projectID: String, clips: [EDLClip]) throws -> [String: ClipRenderState] {
        let directory = outputDirectory.appending(path: projectID)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [:] }
        var restored: [String: ClipRenderState] = [:]
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for clip in clips where url.lastPathComponent == Self.exportName(clip: clip) {
                restored[clip.id] = .done(url)
            }
        }
        return restored
    }

    private static func exportName(clip: EDLClip) -> String { "\(clip.id).mp4" }

    /// Renders one clip of the current result into the project's export directory. Task
    /// cancellation returns the clip to `.idle`; it is not a failure.
    public func render(clip: EDLClip) async {
        guard let result else {
            renders[clip.id] = .failed("no slicing result to render")
            return
        }
        renders[clip.id] = .rendering(0)
        do {
            let directory = outputDirectory.appending(path: result.projectID)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let output = directory.appending(path: Self.exportName(clip: clip))
            let url = try await dependencies.render(result.sourceURL, clip, result.cues, output) { [weak self] value in
                Task { @MainActor in
                    if case .rendering = self?.renders[clip.id] { self?.renders[clip.id] = .rendering(value) }
                }
            }
            renders[clip.id] = .done(url)
        } catch is CancellationError {
            renders[clip.id] = .idle
        } catch {
            renders[clip.id] = .failed(ErrorText.describe(error))
        }
    }

    /// Back to the idle screen. The project stays saved; only scratch audio is deleted, and a
    /// failed delete is shown.
    public func reset() {
        result = nil
        renders = [:]
        startedAt = nil
        activeLocaleIdentifier = nil
        do {
            try purgeScratch()
            stage = .idle
        } catch {
            stage = .failed(ErrorText.describe(error))
        }
    }

    /// Empties the scratch directory (extracted audio, picker copies that were never adopted).
    private func purgeScratch() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: scratchDirectory.path) {
            for url in try fm.contentsOfDirectory(at: scratchDirectory, includingPropertiesForKeys: nil) {
                try fm.removeItem(at: url)
            }
        }
        try fm.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
    }
}

/// Human-readable error text that keeps the typed case name (e.g. `missingAPIKey`) visible.
