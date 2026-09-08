// Why: a two-hour transcription plus a DeepSeek call is minutes of work that used to vanish the
// moment the user left the workbench. A project is one imported video with whatever the pipeline
// has produced so far (transcript, then EDL), written to disk after each step, so reopening the app
// resumes from the last finished step instead of from zero. Application Support (not Caches) so
// the system never deletes it; excluded from backup because the source video is large.

import Foundation
import LiveSliceCore

public enum ProjectStoreError: Error, Equatable, Sendable, LocalizedError {
    case sourceMissing(String)
    case corruptRecord(String)

    public var errorDescription: String? {
        switch self {
        case .sourceMissing(let id): "项目 \(id) 的源视频已不在设备上"
        case .corruptRecord(let path): "项目文件无法读取（\(path)）"
        }
    }
}

/// One imported video and the pipeline output saved so far. `srt`/`document` are nil until
/// their step has finished; the file on disk is the checkpoint. Each output carries the inputs it
/// was produced with (`transcribedWith`, `slicedWith`) so a later run can tell "still valid" from
/// "settings changed"; both are nil on records written before that was tracked.
public struct ProjectRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let createdAt: Date
    public let sourceFileName: String
    /// `SourceFingerprint` of the imported file; nil on records adopted before fingerprinting.
    public var sourceFingerprint: String?
    public var localeIdentifier: String?
    public var srt: String?
    /// `ASRLocalePreference.identifier` in force when `srt` was produced.
    public var transcribedWith: String?
    public var document: EDLDocument?
    /// `PipelineReuse.sliceKey` in force when `document` was produced.
    public var slicedWith: String?

    public init(
        id: String, createdAt: Date, sourceFileName: String, sourceFingerprint: String? = nil,
        localeIdentifier: String? = nil, srt: String? = nil, transcribedWith: String? = nil,
        document: EDLDocument? = nil, slicedWith: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceFileName = sourceFileName
        self.sourceFingerprint = sourceFingerprint
        self.localeIdentifier = localeIdentifier
        self.srt = srt
        self.transcribedWith = transcribedWith
        self.document = document
        self.slicedWith = slicedWith
    }

    /// Title shown in the project list: the first clip's title once sliced, else nothing.
    public var title: String? { document?.clips.first?.title }
    public var clipCount: Int {
        guard let document else { return 0 }
        return document.clips.count
    }
    public var isSliced: Bool { document != nil }
    public var isTranscribed: Bool { srt != nil }
}

public struct ProjectStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// Default location: Application Support/Projects, kept out of iCloud/iTunes backups.
    public static func applicationSupport() throws -> ProjectStore {
        var url = URL.applicationSupportDirectory.appending(path: "Projects")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        return ProjectStore(root: url)
    }

    public func directory(of id: String) -> URL { root.appending(path: id) }

    public func sourceURL(of record: ProjectRecord) -> URL {
        directory(of: record.id).appending(path: record.sourceFileName)
    }

    private func recordURL(of id: String) -> URL { directory(of: id).appending(path: "project.json") }

    /// Moves an imported file into a new project directory (same volume, so this is a rename).
    public func adopt(sourceURL: URL, fingerprint: String? = nil) throws -> ProjectRecord {
        let id = UUID().uuidString
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let record = ProjectRecord(id: id, createdAt: Date(), sourceFileName: "source.\(ext)", sourceFingerprint: fingerprint)
        try FileManager.default.createDirectory(at: directory(of: id), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: sourceURL, to: self.sourceURL(of: record))
        try save(record)
        return try load(id: id) // what the disk has (Date precision) is the record, not the in-memory draft
    }

    public func save(_ record: ProjectRecord) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Seconds as a Double keep sub-second order between imports; ISO 8601 would drop it.
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(record).write(to: recordURL(of: record.id), options: .atomic)
    }

    public func load(id: String) throws -> ProjectRecord {
        let url = recordURL(of: id)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        do {
            return try decoder.decode(ProjectRecord.self, from: data)
        } catch {
            throw ProjectStoreError.corruptRecord(url.path)
        }
    }

    /// Every saved project, newest first. A directory without a readable record is an error, not skipped.
    public func list() throws -> [ProjectRecord] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
        var records: [ProjectRecord] = []
        for entry in entries where try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
            records.append(try load(id: entry.lastPathComponent))
        }
        return records.sorted { $0.createdAt > $1.createdAt }
    }

    /// Fails if the source video has been removed from under the project.
    public func requireSource(of record: ProjectRecord) throws -> URL {
        let url = sourceURL(of: record)
        guard FileManager.default.fileExists(atPath: url.path) else { throw ProjectStoreError.sourceMissing(record.id) }
        return url
    }

    public func delete(id: String) throws {
        try FileManager.default.removeItem(at: directory(of: id))
    }
}
