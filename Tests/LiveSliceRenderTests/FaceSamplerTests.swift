// Why: FaceSampler must fail loudly when Vision or frame sampling cannot run. Tests assert every case.

import CoreGraphics
import Foundation
import Testing
@testable import LiveSliceRender

@Suite("FaceSampler")
struct FaceSamplerTests {
    @Test func errorEquality() {
        #expect(FaceSamplerError.imageGeneratorUnavailable == .imageGeneratorUnavailable)
        #expect(FaceSamplerError.frameCopyFailed(1.5) == .frameCopyFailed(1.5))
        #expect(FaceSamplerError.frameCopyFailed(1.0) != .frameCopyFailed(2.0))
        #expect(FaceSamplerError.visionFailed("x") == .visionFailed("x"))
        #expect(FaceSamplerError.visionFailed("a") != .visionFailed("b"))
    }

    @Test func errorDescriptionsAreChinese() {
        #expect(FaceSamplerError.imageGeneratorUnavailable.errorDescription?.contains("取帧") == true)
        #expect(FaceSamplerError.frameCopyFailed(3.2).errorDescription?.contains("3.2") == true)
        #expect(FaceSamplerError.visionFailed("boom").errorDescription?.contains("boom") == true)
    }

    @Test func detectFacesOnBlankImageReturnsEmpty() throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = ctx.makeImage() else {
            Issue.record("Could not make blank CGImage")
            return
        }
        let faces = try FaceSampler.detectFaces(in: image)
        #expect(faces.isEmpty)
    }

    @Test func sampleCountIsFive() {
        #expect(FaceSampler.sampleCount == 5)
    }
}
