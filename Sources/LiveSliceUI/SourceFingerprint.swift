// Why: importing the same video twice used to mean transcribing and slicing it twice. A fingerprint
// of the picked file lets the session recognise a video it already has a project for and open that
// project instead. Hashing a whole two-hour 4K file would take longer than the import itself, so
// the fingerprint covers the byte count plus three fixed 8 MiB windows (head, middle, tail): two
// different recordings with identical size and identical bytes at all three places do not occur in
// practice, and a re-encode changes every window.

import CryptoKit
import Foundation

enum SourceFingerprintError: Error, Equatable, Sendable, LocalizedError {
    case unreadable(String)
    case shortRead(String, expected: Int, got: Int)

    var errorDescription: String? {
        switch self {
        case .unreadable(let path): "无法读取导入的视频文件（\(path)）"
        case .shortRead(let path, let expected, let got): "视频文件读取不完整（\(path)，需要 \(expected) 字节，只读到 \(got)）"
        }
    }
}

public enum SourceFingerprint {
    /// Bytes hashed at each of the three windows.
    public static let windowBytes = 8 << 20
    /// Prefix so a future change to the sampling scheme never matches an old value by accident.
    static let scheme = "v1"

    /// `v1-<byte count>-<sha256>`; files up to three windows long are hashed completely.
    public static func compute(url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = (attributes[.size] as? NSNumber)?.intValue else { throw SourceFingerprintError.unreadable(url.path) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }

        var hasher = SHA256()
        hasher.update(data: Data("\(scheme):\(size):".utf8))
        for offset in windowOffsets(size: size) {
            try handle.seek(toOffset: UInt64(offset))
            let length = min(windowBytes, size - offset)
            let chunk = try handle.read(upToCount: length) ?? Data()
            guard chunk.count == length else {
                throw SourceFingerprintError.shortRead(url.path, expected: length, got: chunk.count)
            }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return "\(scheme)-\(size)-\(digest)"
    }

    /// Start offsets of the windows to hash: the whole file when it fits in three windows,
    /// otherwise head, centre and tail.
    static func windowOffsets(size: Int) -> [Int] {
        guard size > 3 * windowBytes else { return stride(from: 0, to: size, by: windowBytes).map { $0 } }
        return [0, (size - windowBytes) / 2, size - windowBytes]
    }
}
