// Why: creators publish from the Photos app, so "save to Photos" is the final step of the product.
// The saver asks for add-only access and reports a denied authorization as an error rather than
// pretending the video was saved.

import Foundation
import Photos

public enum PhotoLibraryError: Error, Equatable, Sendable {
    case accessDenied(PHAuthorizationStatus)
}

public enum PhotoLibrarySaver {
    /// Adds the video file to the user's photo library.
    public static func save(videoURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw PhotoLibraryError.accessDenied(status) }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
        }
    }
}
