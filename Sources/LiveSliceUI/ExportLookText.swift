// Why: display strings and save-button titles for the export look sheet. Kept pure so tests can
// assert copy without mounting SwiftUI.

import LiveSliceRender
import Foundation

enum ExportLookText {
    static func framingTitle(_ mode: FramingMode) -> String {
        switch mode {
        case .sourceAspect: "原比例"
        case .phonePortrait: "手机竖屏"
        case .portraitFit: "竖屏完整"
        }
    }

    static func framingNote(_ mode: FramingMode) -> String {
        switch mode {
        case .sourceAspect: "保持素材自己的宽高比，最长边不超过 1920"
        case .phonePortrait: "裁成 9:16；默认同人脸，可在成片样式预览上拖动改取景，点「跟脸」恢复自动"
        case .portraitFit: "9:16 画布，完整画面居中，两侧或上下留黑边"
        }
    }

    static func styleTitle(_ style: CaptionStyle) -> String {
        switch style {
        case .clean: "简洁"
        case .highlightWord: "高亮词"
        case .none: "无字幕"
        }
    }

    static func styleNote(_ style: CaptionStyle, hasWords: Bool) -> String {
        switch style {
        case .clean: "试看即时显示；导出时烧进画面"
        case .highlightWord: hasWords ? "说到哪个词亮哪个词" : "这个项目是旧版本转写的，没有逐词时间"
        case .none: "试看不叠字；导出只切画面和声音"
        }
    }

    static func positionTitle(_ position: CaptionPosition) -> String {
        switch position {
        case .bottom: "下"
        case .middle: "中"
        case .top: "上"
        }
    }

    /// Main button text names every non-default look so the file is never a surprise.
    static func saveTitle(
        style: CaptionStyle, position: CaptionPosition, framing: FramingMode = .sourceAspect,
        tune: CaptionTune = .standard
    ) -> String {
        var parts: [String] = []
        if framing != .sourceAspect { parts.append(framingTitle(framing)) }
        if style != .clean { parts.append(styleTitle(style)) }
        if tune != .standard { parts.append("自定义字幕") }
        else if position != .bottom, style.burnsCaptions { parts.append(positionTitle(position)) }
        return parts.isEmpty ? "保存到相册" : "保存到相册 · \(parts.joined(separator: " · "))"
    }

    static func title(_ style: CaptionStyle) -> String { styleTitle(style) }
    static func note(_ style: CaptionStyle, hasWords: Bool) -> String { styleNote(style, hasWords: hasWords) }
}

/// Compatibility alias used by older call sites / tests.
typealias CaptionStyleText = ExportLookText

enum ExportLookSection: String, CaseIterable, Identifiable {
    case framing, captions
    var id: String { rawValue }
    var title: String {
        switch self {
        case .framing: "画幅"
        case .captions: "字幕"
        }
    }
}

