import Foundation
import Testing
@testable import LiveSliceUI

struct SourceFingerprintTests {
    private func file(_ bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "fp-\(UUID().uuidString).bin")
        try Data(bytes).write(to: url)
        return url
    }

    @Test func sameBytesSameFingerprintDifferentBytesDifferent() throws {
        let a = try file([1, 2, 3, 4, 5])
        let b = try file([1, 2, 3, 4, 5])
        let c = try file([1, 2, 3, 4, 6])
        let fa = try SourceFingerprint.compute(url: a)
        #expect(fa == (try SourceFingerprint.compute(url: b)))
        #expect(fa != (try SourceFingerprint.compute(url: c)))
        #expect(fa.hasPrefix("v1-5-"))
        #expect(fa.count == "v1-5-".count + 64)
    }

    @Test func sizeAloneDistinguishes() throws {
        let short = try file([0, 0, 0])
        let long = try file([0, 0, 0, 0])
        #expect(try SourceFingerprint.compute(url: short) != (try SourceFingerprint.compute(url: long)))
    }

    @Test func smallFilesAreHashedCompletelyLargeOnesAtThreeWindows() {
        let w = SourceFingerprint.windowBytes
        #expect(SourceFingerprint.windowOffsets(size: 10) == [0])
        #expect(SourceFingerprint.windowOffsets(size: 2 * w + 1) == [0, w, 2 * w])
        #expect(SourceFingerprint.windowOffsets(size: 3 * w) == [0, w, 2 * w])
        #expect(SourceFingerprint.windowOffsets(size: 100 * w) == [0, (100 * w - w) / 2, 99 * w])
    }

    @Test func largeFileChangeOutsideTheWindowsIsInvisibleByDesignInsideIsNot() throws {
        // Four windows long: bytes strictly between the sampled windows are not read.
        let w = SourceFingerprint.windowBytes
        var bytes = [UInt8](repeating: 7, count: 4 * w)
        let base = try file(bytes)
        bytes[w + 10] = 8 // between head window and the centre window (which starts at 1.5w)
        let outside = try file(bytes)
        bytes[w + 10] = 7
        bytes[4 * w - 1] = 9 // last byte: inside the tail window
        let inside = try file(bytes)
        let fBase = try SourceFingerprint.compute(url: base)
        #expect(fBase == (try SourceFingerprint.compute(url: outside)))
        #expect(fBase != (try SourceFingerprint.compute(url: inside)))
    }

    @Test func missingFileIsATypedError() {
        let url = FileManager.default.temporaryDirectory.appending(path: "fp-missing-\(UUID().uuidString).bin")
        #expect(throws: Error.self) { try SourceFingerprint.compute(url: url) }
        // A directory has a size but no readable bytes: also an error, not an empty fingerprint.
        #expect(throws: Error.self) { try SourceFingerprint.compute(url: FileManager.default.temporaryDirectory) }
    }
}
