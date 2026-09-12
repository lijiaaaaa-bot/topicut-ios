// Why: captions sit in one band on the frame; users need a few fixed places (lower third, centre,
// upper third) rather than free dragging — one choice remembered across projects, applied the same
// way on the live preview and when burning into an export. Geometry stays in SubtitleStyle; this
// only picks which bottomInset to use after scaling.

import CoreGraphics
import Foundation

public enum CaptionPosition: String, CaseIterable, Codable, Equatable, Sendable {
    /// Default lower third (the 1.0 `vertical1080p` inset).
    case bottom
    /// Vertically centred band.
    case middle
    /// Same margin from the top as `bottom` has from the bottom.
    case top

    /// Appended after the style suffix in the export file name. Empty for `bottom` so existing
    /// bottom-placed exports still match.
    public var exportSuffix: String {
        switch self {
        case .bottom: ""
        case .middle: "-mid"
        case .top: "-top"
        }
    }

    /// Scales `base` to `renderSize`, then replaces `bottomInset` for this position.
    public func style(from base: SubtitleStyle = .vertical1080p, renderSize: CGSize) -> SubtitleStyle {
        let scaled = base.scaled(to: renderSize)
        let inset: CGFloat
        switch self {
        case .bottom:
            inset = scaled.bottomInset
        case .middle:
            inset = max(0, (renderSize.height - scaled.bandHeight) / 2)
        case .top:
            inset = max(0, renderSize.height - scaled.bandHeight - scaled.bottomInset)
        }
        return SubtitleStyle(
            fontSize: scaled.fontSize,
            bottomInset: inset,
            horizontalInset: scaled.horizontalInset,
            strokeWidth: scaled.strokeWidth
        )
    }
}
