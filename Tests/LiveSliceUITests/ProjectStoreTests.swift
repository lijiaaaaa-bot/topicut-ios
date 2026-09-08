import Foundation
import Testing
@testable import LiveSliceUI
import LiveSliceCore

struct ProjectStoreTests {
    static func makeStore() throws -> (ProjectStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "liveslice-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (ProjectStore(root: dir.appending(path: "projects")), dir)
    }

    static func picked(in dir: URL, ext: String = "MOV") throws -> URL {
        let url = dir.appending(path: "\(UUID().uuidString).\(ext)")
        try Data("video".utf8).write(to: url)
        return url
    }

    @Test func adoptMovesTheFileAndWritesARecord() throws {
        let (store, dir) = try Self.makeStore()
        let picked = try Self.picked(in: dir)
        let record = try store.adopt(sourceURL: picked)
        #expect(!FileManager.default.fileExists(atPath: picked.path))
        #expect(record.sourceFileName == "source.MOV")
        #expect(FileManager.default.fileExists(atPath: store.sourceURL(of: record).path))
        #expect(try store.requireSource(of: record) == store.sourceURL(of: record))
        #expect(try store.load(id: record.id) == record)
        #expect(!record.isTranscribed && !record.isSliced && record.title == nil && record.clipCount == 0)
    }

    @Test func listIsNewestFirstAndRoundTripsCheckpoints() throws {
        let (store, dir) = try Self.makeStore()
        let first = try store.adopt(sourceURL: try Self.picked(in: dir))
        var second = try store.adopt(sourceURL: try Self.picked(in: dir), fingerprint: "v1-5-abc")
        second.srt = try SRTWriter.serialize(SessionFixtures.cues)
        second.localeIdentifier = "en_US"
        second.transcribedWith = "auto"
        second.document = try SessionFixtures.document()
        second.slicedWith = "deepseek-chat|https://api.deepseek.com"
        try store.save(second)

        let listed = try store.list()
        #expect(listed.map(\.id) == [second.id, first.id])
        #expect(listed[0].title == "测试话题")
        #expect(listed[0].clipCount == 1)
        #expect(try SRTParser.parse(try #require(listed[0].srt)) == SessionFixtures.cues)
        #expect(listed[0].document == (try SessionFixtures.document()))
        #expect(listed[0] == second, "provenance fields round-trip")
        #expect(listed[1].sourceFingerprint == nil)
        #expect(listed[1].transcribedWith == nil)
    }

    @Test func recordsWrittenBeforeProvenanceStillDecode() throws {
        let (store, _) = try Self.makeStore()
        let id = "legacy"
        try FileManager.default.createDirectory(at: store.directory(of: id), withIntermediateDirectories: true)
        let json = """
        {"id":"legacy","createdAt":1700000000,"sourceFileName":"source.mov","localeIdentifier":"zh_CN","srt":"1\\n00:00:01,000 --> 00:00:02,000\\n你好\\n"}
        """
        try Data(json.utf8).write(to: store.directory(of: id).appending(path: "project.json"))
        let record = try store.load(id: id)
        #expect(record.isTranscribed)
        #expect(record.sourceFingerprint == nil)
        #expect(record.transcribedWith == nil)
        #expect(record.slicedWith == nil)
    }

    @Test func emptyOrMissingRootListsNothing() throws {
        let (store, _) = try Self.makeStore()
        #expect(try store.list().isEmpty)
    }

    @Test func corruptRecordIsATypedError() throws {
        let (store, dir) = try Self.makeStore()
        let record = try store.adopt(sourceURL: try Self.picked(in: dir))
        try Data("{not json".utf8).write(to: store.directory(of: record.id).appending(path: "project.json"))
        #expect(throws: ProjectStoreError.corruptRecord(store.directory(of: record.id).appending(path: "project.json").path)) {
            try store.list()
        }
    }

    @Test func missingSourceIsATypedErrorWithAMessage() throws {
        let (store, dir) = try Self.makeStore()
        let record = try store.adopt(sourceURL: try Self.picked(in: dir))
        try FileManager.default.removeItem(at: store.sourceURL(of: record))
        #expect(throws: ProjectStoreError.sourceMissing(record.id)) { try store.requireSource(of: record) }
        #expect(ProjectStoreError.sourceMissing("x").errorDescription == "项目 x 的源视频已不在设备上")
    }

    @Test func deleteRemovesTheWholeProjectDirectory() throws {
        let (store, dir) = try Self.makeStore()
        let record = try store.adopt(sourceURL: try Self.picked(in: dir))
        try store.delete(id: record.id)
        #expect(!FileManager.default.fileExists(atPath: store.directory(of: record.id).path))
        #expect(try store.list().isEmpty)
    }
}
