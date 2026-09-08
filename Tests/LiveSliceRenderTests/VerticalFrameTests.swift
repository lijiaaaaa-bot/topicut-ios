import CoreGraphics
import Testing
@testable import LiveSliceRender

struct VerticalFrameTests {
    private func approx(_ a: CGPoint, _ b: CGPoint, tolerance: CGFloat = 0.01) -> Bool {
        abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance
    }

    @Test func rotatedPortraitPhoneFootageIsUpright() {
        // Typical iPhone portrait: 1920x1080 natural with a 90° rotation transform.
        let rotation = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
        let oriented = VerticalFrame.orientedSize(naturalSize: CGSize(width: 1920, height: 1080), preferredTransform: rotation)
        #expect(oriented == CGSize(width: 1080, height: 1920))
        let transform = VerticalFrame.fitTransform(
            naturalSize: CGSize(width: 1920, height: 1080), preferredTransform: rotation, renderSize: oriented
        )
        let centre = CGPoint(x: 960, y: 540).applying(transform)
        #expect(approx(centre, CGPoint(x: 540, y: 960)))
        // Natural top-left (0,0) rotates to the top-right corner of the upright frame.
        #expect(approx(CGPoint.zero.applying(transform), CGPoint(x: 1080, y: 0)))
    }

    @Test func sameShapeCanvasIsAPureScale() {
        // 4K landscape into its capped 1920x1080 output: scale 0.5, no offset, nothing cropped.
        let transform = VerticalFrame.fitTransform(
            naturalSize: CGSize(width: 3840, height: 2160), preferredTransform: .identity,
            renderSize: CGSize(width: 1920, height: 1080)
        )
        #expect(abs(transform.a - 0.5) < 0.001)
        #expect(approx(CGPoint.zero.applying(transform), .zero))
        #expect(approx(CGPoint(x: 3840, y: 2160).applying(transform), CGPoint(x: 1920, y: 1080)))
    }

    @Test func differentShapeCanvasFitsCompletelyAndCentres() {
        let transform = VerticalFrame.fitTransform(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity,
            renderSize: CGSize(width: 1080, height: 1920)
        )
        #expect(approx(CGPoint(x: 960, y: 540).applying(transform), CGPoint(x: 540, y: 960)))
        #expect(approx(CGPoint.zero.applying(transform), CGPoint(x: 0, y: 656.25)))
        #expect(approx(CGPoint(x: 1920, y: 1080).applying(transform), CGPoint(x: 1080, y: 1263.75)))
    }

    @Test func sourceAspectCapsLongestEdgeAndUsesEvenDimensions() {
        #expect(
            VerticalFrame.sourceRenderSize(orientedSize: CGSize(width: 3840, height: 2160))
                == CGSize(width: 1920, height: 1080)
        )
        #expect(
            VerticalFrame.sourceRenderSize(orientedSize: CGSize(width: 1001, height: 777))
                == CGSize(width: 1000, height: 776)
        )
        #expect(VerticalFrame.sourceRenderSize(orientedSize: CGSize(width: 640, height: 360)) == CGSize(width: 640, height: 360))
    }
}
