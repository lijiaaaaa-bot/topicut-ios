// Why: PhotosPicker hands over a security-scoped temporary file that disappears when the
// transferable is released; ASR and rendering need a stable URL for minutes. Copying into the app's
// scratch directory once, here, is the only file-handling the picker path does.

import CoreTransferable
import Foundation

public struct PickedVideo: Transferable, Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            PickedVideo(url: try Self.copyIntoScratch(received.file))
        }
    }

    /// Copies a picked or imported file into the scratch directory under a unique name.
    public static func copyIntoScratch(_ source: URL) throws -> URL {
        let directory = AppDirectories.scratch.appending(path: "imports")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: "\(UUID().uuidString).\(source.pathExtension.isEmpty ? "mov" : source.pathExtension)")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
}
