import Foundation
import Testing
@testable import LiveSliceUI
import LiveSliceCore
import LiveSliceKeychain

/// Fixtures shared by the injected dependency closures (which run off the main actor).
enum SessionFixtures {
    static let cues = [SRTCue(index: 1, start: 1, end: 13, text: "话题主体"), SRTCue(index: 2, start: 16, end: 22, text: "收束")]
    static let words = [
        TimedToken(text: "话题", start: 1, end: 6), TimedToken(text: "主体", start: 6, end: 13), TimedToken(text: "收束", start: 16, end: 22),
    ]

    static func clip() throws -> EDLClip {
        try EDLClip(
            id: "f_01_c_01", title: "测试话题", reason: "完整", score: 0.8, tags: [], category: "观点论述",
            frameworkId: "f_01", frameworkTitle: "框架", mode: EDLClip.modeCompressedConcat,
            segments: [EDLSegment(startSec: 1, endSec: 13, reason: nil), EDLSegment(startSec: 16, endSec: 22, reason: nil)],
            removedSegments: [EDLSegment(startSec: 13, endSec: 16, reason: "答题")]
        )
    }

    static func document() throws -> EDLDocument {
        let strategy = SlicingStrategy.topicCompleteGeneral
        return EDLDocument(
            generatedAt: Date(timeIntervalSince1970: 0), strategy: strategy,
            clipCountPolicy: try strategy.clipCountPolicy(forDurationSeconds: 21),
            transcript: EDLTranscriptInfo(cueCount: 2, startSec: 1, endSec: 22), clips: [try clip()], llm: nil
        )
    }
}

/// A session with its own settings, project store and work directories under a temp root.
@MainActor
struct SessionHarness {
    let session: SliceSession
    let settings: AppSettings
    let store: ProjectStore
    let scratch: URL
    let output: URL

    init(_ dependencies: SessionDependencies, key: String? = "sk-test") throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "liveslice-ui-\(UUID().uuidString)")
        scratch = dir.appending(path: "scratch")
        output = dir.appending(path: "out")
        store = ProjectStore(root: dir.appending(path: "projects"))
        settings = try Self.settings(withKey: key)
        session = SliceSession(
            settings: settings, dependencies: dependencies, store: store,
            scratchDirectory: scratch, outputDirectory: output
        )
    }

    static func settings(withKey key: String?) throws -> AppSettings {
        let suite = "liveslice.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = APIKeyStore(service: "com.jiajiali.liveslice.tests.\(UUID().uuidString)")
        if let key { try store.save(key) }
        return try AppSettings(store: store, defaults: defaults)
    }

    /// A picked file in the scratch imports folder, as PickedVideo would leave it.
    func importedSource(named name: String = "picked.mov", contents: String = "video") throws -> URL {
        let imports = scratch.appending(path: "imports")
        try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
        let url = imports.appending(path: name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    /// A saved project with a source file and whatever checkpoints the test needs.
    func savedProject(
        srt: String? = nil, document: EDLDocument? = nil, source: Bool = true,
        transcribedWith: String? = nil, slicedWith: String? = nil
    ) throws -> ProjectRecord {
        var record = try store.adopt(sourceURL: try importedSource(named: "\(UUID().uuidString).mov"))
        record.srt = srt
        record.localeIdentifier = srt == nil ? nil : "zh_CN"
        record.transcribedWith = transcribedWith
        record.document = document
        record.slicedWith = slicedWith
        try store.save(record)
        if !source { try FileManager.default.removeItem(at: store.sourceURL(of: record)) }
        return record
    }

    /// Import → ASR → stop at 切片工作室 → confirm the paid slice (ADR-0028).
    /// If the project already has a current EDL (reopen / fingerprint hit), stays at `.ready`.
    func startThroughSlice(sourceURL: URL? = nil) async throws {
        await session.start(sourceURL: try sourceURL ?? importedSource())
        if case .awaitingSlice = session.stage {
            #expect(session.awaitingSlice != nil)
            await session.confirmSlice()
        }
    }

    /// Open a project; if the pipeline stops at the studio gate, confirm the slice.
    func openThroughSlice(_ record: ProjectRecord) async {
        await session.open(record)
        if case .awaitingSlice = session.stage {
            await session.confirmSlice()
        }
    }
}
