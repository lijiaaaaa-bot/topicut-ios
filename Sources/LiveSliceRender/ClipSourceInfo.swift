// Why: the AVAssetTrack only weakly holds its asset; keeping SourceInfo together with the
// composition that uses its tracks prevents the opaque -12780 export failure.

import AVFoundation
import CoreGraphics
import Foundation

struct SourceInfo: @unchecked Sendable {
    let asset: AVURLAsset
    let videoTrack: AVAssetTrack
    let audioTrack: AVAssetTrack?
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform

    static func load(url: URL) async throws -> SourceInfo {
        let asset = AVURLAsset(url: url)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw ClipRendererError.noVideoTrack(url)
        }
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let (naturalSize, transform) = try await video.load(.naturalSize, .preferredTransform)
        return SourceInfo(asset: asset, videoTrack: video, audioTrack: audio, naturalSize: naturalSize, preferredTransform: transform)
    }
}
