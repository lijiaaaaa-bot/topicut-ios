// Why: once we know where faces sit in the oriented frame, the 9:16 crop is pure geometry —
// unit-tested without Vision or video. Focus is normalised 0…1 in oriented space (origin top-left
// of the displayed frame); the crop window is the largest 9:16 rect that still contains the focus
// as close to centre as the bounds allow.

import CoreGraphics
import Foundation

public enum FaceFocus {
    /// Largest 9:16 window inside `oriented` whose centre is as close as possible to `focus`
    /// (normalised 0…1, top-left origin). `zoom` ≥ 1 tightens the window around the focus
    /// (1 = widest legal 9:16; 2 ≈ half that size). Empty `oriented` yields `.zero`.
    public static func phoneCropWindow(oriented: CGSize, focus: CGPoint, zoom: CGFloat = 1) -> CGRect {
        guard oriented.width > 0, oriented.height > 0 else { return .zero }
        let targetAspect: CGFloat = 9 / 16
        let sourceAspect = oriented.width / oriented.height
        let maxCrop: CGSize
        if sourceAspect > targetAspect {
            maxCrop = CGSize(width: oriented.height * targetAspect, height: oriented.height)
        } else {
            maxCrop = CGSize(width: oriented.width, height: oriented.width / targetAspect)
        }
        let scale = 1 / max(1, zoom)
        let crop = CGSize(width: maxCrop.width * scale, height: maxCrop.height * scale)
        let fx = min(1, max(0, focus.x)) * oriented.width
        let fy = min(1, max(0, focus.y)) * oriented.height
        let x = min(max(0, fx - crop.width / 2), oriented.width - crop.width)
        let y = min(max(0, fy - crop.height / 2), oriented.height - crop.height)
        return CGRect(x: x, y: y, width: crop.width, height: crop.height)
    }

    /// Area-weighted centre of face boxes (Vision normalised, origin bottom-left) mapped into
    /// oriented top-left normalised space. Nil when there are no faces.
    public static func focus(
        faces: [CGRect], oriented: CGSize
    ) -> CGPoint? {
        guard !faces.isEmpty, oriented.width > 0, oriented.height > 0 else { return nil }
        var sx: CGFloat = 0, sy: CGFloat = 0, w: CGFloat = 0
        for box in faces {
            let area = max(0, box.width) * max(0, box.height)
            guard area > 0 else { continue }
            // Vision: origin bottom-left, y up. Oriented display: origin top-left, y down.
            let cx = box.midX
            let cy = 1 - box.midY
            sx += cx * area
            sy += cy * area
            w += area
        }
        guard w > 0 else { return nil }
        return CGPoint(x: sx / w, y: sy / w)
    }
}
