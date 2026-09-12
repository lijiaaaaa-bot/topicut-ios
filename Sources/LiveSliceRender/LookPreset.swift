// Why: fixed 成片标签 (ADR-0027) so the studio's primary path is one tap, not a wall of knobs.
// Each preset writes CaptionStyle + FramingMode + CaptionTune; free knobs and NL fill the same fields.

import Foundation

public enum LookPreset: String, CaseIterable, Identifiable, Sendable {
    case sourceClean
    case phoneHighlight
    case phonePlain
    case fitClean
    case sourceNone

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sourceClean: "原比例 · 简洁"
        case .phoneHighlight: "竖屏跟人 · 高亮词"
        case .phonePlain: "竖屏跟人 · 无字幕"
        case .fitClean: "竖屏完整 · 简洁"
        case .sourceNone: "原比例 · 无字幕"
        }
    }

    public var note: String {
        switch self {
        case .sourceClean: "保持素材宽高比"
        case .phoneHighlight: "9:16 裁切，说到的词高亮"
        case .phonePlain: "9:16 裁切，不烧字幕"
        case .fitClean: "9:16 画布，画面完整不裁"
        case .sourceNone: "原比例，不烧字幕"
        }
    }

    public var style: CaptionStyle {
        switch self {
        case .sourceClean, .fitClean: .clean
        case .phoneHighlight: .highlightWord
        case .phonePlain, .sourceNone: .none
        }
    }

    public var framing: FramingMode {
        switch self {
        case .sourceClean, .sourceNone: .sourceAspect
        case .phoneHighlight, .phonePlain: .phonePortrait
        case .fitClean: .portraitFit
        }
    }

    public var tune: CaptionTune {
        switch self {
        case .sourceClean, .fitClean, .phonePlain, .sourceNone:
            .standard
        case .phoneHighlight:
            CaptionTune(bandY: 0, fontScale: 1, textHex: "FFFFFF", accentHex: "FFD60A")
        }
    }
}
