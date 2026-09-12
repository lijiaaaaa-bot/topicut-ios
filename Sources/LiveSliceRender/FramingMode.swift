// Why: export can keep the source shape or cut a 9:16 phone frame. Face guidance (Vision) picks
// where that phone window sits when people are on screen; without faces the window is centred.
// That is the mode's geometry, not a silent failure of a required face (ADR-0025).

import CoreGraphics
import Foundation

public enum FramingMode: String, CaseIterable, Codable, Equatable, Sendable {
    /// Source aspect, longest edge capped at 1920 (ADR-0016 default).
    case sourceAspect
    /// 9:16 phone canvas. Crop window follows faces when Vision finds them, else the frame centre.
    case phonePortrait
    /// 9:16 canvas with the whole frame letterboxed (no crop) (ADR-0027).
    case portraitFit

    public var exportSuffix: String {
        switch self {
        case .sourceAspect: ""
        case .phonePortrait: "-9x16"
        case .portraitFit: "-fit9x16"
        }
    }

    /// Output pixel size for this mode given the oriented source.
    public func renderSize(orientedSource: CGSize) -> CGSize {
        switch self {
        case .sourceAspect:
            return VerticalFrame.sourceRenderSize(orientedSize: orientedSource)
        case .phonePortrait, .portraitFit:
            return CGSize(width: 1080, height: 1920)
        }
    }
}
