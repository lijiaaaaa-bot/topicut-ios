// Why: the export has more than one caption look (ADR-0023) and the choice must survive in the
// file name, so an MP4 cut with one style never passes for another when the user switches.
// Geometry (font size, insets) stays in SubtitleStyle; this is only which look is burnt in.

import Foundation

public enum CaptionStyle: String, CaseIterable, Codable, Equatable, Sendable {
    /// 1.0 look: white text, black outline, no backdrop.
    case clean
    /// Dark rounded backdrop behind each line, white text, the word being spoken in the accent colour.
    /// Needs word timings; without them the render is an error, not a silent downgrade to `clean`.
    case highlightWord
    /// No captions burnt in.
    case none

    /// Appended to `<clipID>` in the export file name. Empty for `clean` so 1.0 exports still match.
    public var exportSuffix: String {
        switch self {
        case .clean: ""
        case .highlightWord: "-words"
        case .none: "-plain"
        }
    }

    public var burnsCaptions: Bool { self != .none }
}
