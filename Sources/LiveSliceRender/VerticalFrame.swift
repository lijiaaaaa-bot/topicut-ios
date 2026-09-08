// Why: the export keeps the source's own shape. That still needs matrix work: phone footage is
// often rotated in metadata (preferredTransform), and 4K sources are capped at 1920 on the longest
// edge. Keeping that algebra pure and tested avoids the classic sideways render.

import CoreGraphics
import Foundation

public enum VerticalFrame {
    /// Size of the source as displayed (natural size with the preferred transform applied).
    public static func orientedSize(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    /// Orients the source and scales it to fill `renderSize` exactly (same aspect ratio) or, for a
    /// canvas of another shape, fits it centred with the unused canvas left black.
    public static func fitTransform(
        naturalSize: CGSize, preferredTransform: CGAffineTransform, renderSize: CGSize
    ) -> CGAffineTransform {
        let orientedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let toOrigin = preferredTransform.concatenating(CGAffineTransform(translationX: -orientedRect.minX, y: -orientedRect.minY))
        let oriented = CGSize(width: abs(orientedRect.width), height: abs(orientedRect.height))
        let scale = min(renderSize.width / oriented.width, renderSize.height / oriented.height)
        let scaled = CGSize(width: oriented.width * scale, height: oriented.height * scale)
        let centre = CGAffineTransform(
            translationX: (renderSize.width - scaled.width) / 2, y: (renderSize.height - scaled.height) / 2
        )
        return toOrigin.concatenating(CGAffineTransform(scaleX: scale, y: scale)).concatenating(centre)
    }

    /// Keeps the source aspect ratio and caps the longest edge at 1920 without upscaling.
    public static func sourceRenderSize(orientedSize: CGSize, maximumDimension: CGFloat = 1920) -> CGSize {
        guard orientedSize.width > 0, orientedSize.height > 0 else { return .zero }
        let scale = min(1, maximumDimension / max(orientedSize.width, orientedSize.height))
        return CGSize(
            width: even(orientedSize.width * scale),
            height: even(orientedSize.height * scale)
        )
    }

    private static func even(_ value: CGFloat) -> CGFloat {
        max(2, floor(value / 2) * 2)
    }
}
