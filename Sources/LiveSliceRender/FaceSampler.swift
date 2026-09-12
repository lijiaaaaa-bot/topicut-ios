// Why: phone-portrait export needs a focus point derived from real frames of this clip. Sample a
// few timestamps, run VNDetectFaceRectanglesRequest, fold the boxes through FaceFocus. No faces
// → nil focus → VerticalFrame centres the 9:16 window. Failures of image generation or Vision are
// typed errors (the export stops), not a silent centre crop that hides the cause.

import AVFoundation
import CoreGraphics
import Foundation
import Vision

public enum FaceSamplerError: Error, Equatable, Sendable, LocalizedError {
    case imageGeneratorUnavailable
    case frameCopyFailed(TimeInterval)
    case visionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .imageGeneratorUnavailable: "无法从视频取帧做人脸取景"
        case .frameCopyFailed(let t): "取帧失败（\(String(format: "%.1f", t)) 秒）"
        case .visionFailed(let detail): "人脸检测失败：\(detail)"
        }
    }
}

public enum FaceSampler {
    /// Sample count across the clip's kept span. Fixed so exports are reproducible for the same file.
    public static let sampleCount = 5

    /// Area-weighted face focus in oriented normalised space, or nil when no face is found.
    public static func focus(
        asset: AVAsset, preferredTransform: CGAffineTransform, naturalSize: CGSize,
        startSec: Double, endSec: Double
    ) async throws -> CGPoint? {
        let oriented = VerticalFrame.orientedSize(naturalSize: naturalSize, preferredTransform: preferredTransform)
        guard endSec > startSec, oriented.width > 0 else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 640, height: 640)

        var faces: [CGRect] = []
        let span = endSec - startSec
        for i in 0..<sampleCount {
            let t = startSec + span * (Double(i) + 0.5) / Double(sampleCount)
            let cgImage: CGImage
            do {
                cgImage = try await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
            } catch {
                throw FaceSamplerError.frameCopyFailed(t)
            }
            faces += try detectFaces(in: cgImage)
        }
        return FaceFocus.focus(faces: faces, oriented: oriented)
    }

    static func detectFaces(in image: CGImage) throws -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw FaceSamplerError.visionFailed(error.localizedDescription)
        }
        return request.results?.map(\.boundingBox) ?? []  // guard-allow: silent-fallback Vision returns nil results for no faces; empty list is the typed "no face" outcome, not a hidden failure
    }
}
