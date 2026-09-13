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
import LiveSliceRender
import Observation

@MainActor
@Observable
public final class SliceSession {
    public internal(set) var stage: SessionStage = .idle
    public internal(set) var result: SessionResult?
    public internal(set) var renders: [String: ClipRenderState] = [:]
    /// When the current pipeline run began; drives the elapsed-time readout, never an estimate.
    public internal(set) var startedAt: Date?
    /// Locale actually used for the current/last transcription (after automatic detection).
    public internal(set) var activeLocaleIdentifier: String?
    /// The AI service the slicing request went to (preset name or host), for the wait screen.
    public internal(set) var slicingService: String?
    /// Saved projects, newest first; refreshed after every store change.
    public private(set) var projects: [ProjectRecord] = []
    /// In-memory head/tail trim while the user drags sliders — preview only until `trimClip` saves.
    public var draftTrimClipID: String?
    public var draftTrimLeading: Double = 0
    public var draftTrimTrailing: Double = 0
    /// Present while `.awaitingSlice` — transcript facts for the 切片工作室 (ADR-0028).
    public internal(set) var awaitingSlice: AwaitingSliceInfo?
    /// Last failed `confirmSlice` error; cleared on the next attempt. Studio shows it in place.
    public internal(set) var sliceError: String?

    let dependencies: SessionDependencies
    let settings: AppSettings
    let store: ProjectStore
    let scratchDirectory: URL
    let outputDirectory: URL

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
        case .idle, .awaitingSlice, .ready, .failed: return false
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

    func beginRun() {
        result = nil
        renders = [:]
        awaitingSlice = nil
        sliceError = nil
        activeLocaleIdentifier = nil
        startedAt = Date()
    }

    /// Drops a stale EDL and its exports: clip ids repeat across runs, so an old MP4 would pass for a new clip.
    func discardSlice(of record: inout ProjectRecord) throws {
        guard record.document != nil else { return }
        record.document = nil
        record.slicedWith = nil
        let exports = outputDirectory.appending(path: record.id)
        if FileManager.default.fileExists(atPath: exports.path) { try FileManager.default.removeItem(at: exports) }
    }

    /// Exports already on disk for this project in the current caption style, keyed back to their clip.
    func restoredRenders(projectID: String, clips: [EDLClip]) throws -> [String: ClipRenderState] {
        let directory = outputDirectory.appending(path: projectID)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [:] }
        var restored: [String: ClipRenderState] = [:]
        let style = settings.captionStyle
        let position = settings.captionPosition
        let tune = settings.captionTune
        let framing = settings.framingMode
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for clip in clips where url.lastPathComponent == Self.exportName(clip: clip, style: style, position: position, tune: tune, framing: framing) {
                restored[clip.id] = .done(url)
            }
        }
        return restored
    }

    /// `<clipID><styleSuffix><tuneSuffix><framingSuffix>.mp4`; defaults keep the 1.0 name.
    static func exportName(
        clip: EDLClip, style: CaptionStyle, position: CaptionPosition,
        tune: CaptionTune = .standard, framing: FramingMode = .sourceAspect
    ) -> String {
        "\(clip.id)\(style.exportSuffix)\(tune.exportSuffix)\(framing.exportSuffix).mp4"
    }

    public func isRendering(_ clipID: String) -> Bool {
        if case .rendering = renders[clipID] { return true }
        return false
    }

    /// Renders one clip of the current result into the project's export directory. Task
    /// cancellation (including interrupted export while cancelled) returns `.idle`. A lone
    /// `AVError.operationInterrupted` retries once, then fails in Chinese.
    public func render(clip: EDLClip) async {
        guard let result else {
            renders[clip.id] = .failed("no slicing result to render")
            return
        }
        renders[clip.id] = .rendering(0)
        do {
            let url = try await RenderInterrupt.run {
                try await self.invokeRender(clip: clip, result: result)
            }
            renders[clip.id] = .done(url)
        } catch is CancellationError {
            renders[clip.id] = .idle
        } catch {
            let recovery: RenderExportRecovery = RenderInterrupt.recovery(
                for: error, taskCancelled: Task.isCancelled
            )
            switch recovery {
            case .idle:
                renders[clip.id] = .idle
            case .retryOnce, .fail:
                renders[clip.id] = .failed(RenderInterrupt.failMessage(error))
            }
        }
    }

    private func invokeRender(clip: EDLClip, result: SessionResult) async throws -> URL {
        let directory = outputDirectory.appending(path: result.projectID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let style = settings.captionStyle
        let position = settings.captionPosition
        let tune = settings.captionTune
        let framing = settings.framingMode
        let cropMap = try store.loadCropFocus(of: result.projectID)
        let cropFocus = cropMap.focus(for: clip.id)
        let cropZoom = cropMap.zoom(for: clip.id)
        let output = directory.appending(
            path: Self.exportName(clip: clip, style: style, position: position, tune: tune, framing: framing)
        )
        return try await dependencies.render(
            result.sourceURL, clip, result.cues, result.words, style, position, tune, framing, cropFocus, cropZoom, output
        ) { [weak self] value in
            Task { @MainActor in
                if case .rendering = self?.renders[clip.id] { self?.renders[clip.id] = .rendering(value) }
            }
        }
    }

    /// Back to the idle screen. The project stays saved; only scratch audio is deleted, and a
    /// failed delete is shown.
    public func reset() {
        result = nil
        renders = [:]
        awaitingSlice = nil
        sliceError = nil
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
